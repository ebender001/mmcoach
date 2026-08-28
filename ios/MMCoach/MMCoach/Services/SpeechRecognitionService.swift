//
//  SpeechRecognitionService.swift
//  MMCoach
//
//  Owns speech recognition for dictating a case narrative. Nothing outside
//  this file talks to Speech/AVFoundation directly.
//
//  PHI hardening (docs/phi-hardening-plan.md): raw audio is recorded
//  locally ONLY. There is no live streaming request to Apple's servers --
//  the mic is captured to a private temp file and nothing else. Once the
//  trainee stops:
//   1. an on-device-only pass (requiresOnDeviceRecognition = true, never
//      touches the network) recognizes that file and screens its
//      transcript with PHIFilterService;
//   2. the flagged spans are muted in the recording (AudioRedactionService);
//   3. ONLY the redacted file is uploaded to Apple's server-based
//      recognizer (contextualStrings still active, for medical-term
//      accuracy) to get the real transcript;
//   4. a category-labeled placeholder is spliced into that transcript at
//      each redacted span's position, and the result is re-screened with
//      PHIFilterService as a defense-in-depth pass.
//  `sessionTranscript` only ever holds that final, already-redacted text
//  -- never a live partial result, and never anything that reflects
//  unscreened audio. `isRecording` stays true for the whole pipeline
//  above, not just while the mic is capturing: DictationController
//  already treats "isRecording went false" as "the definitive final text
//  is ready", so that contract is preserved, just backed by a slower,
//  fully local-then-redacted-upload pipeline instead of a live stream.
//
//  This means dictation requires on-device recognition to be available at
//  all (checked up front in startDictation()) -- there's no way to screen
//  audio for PHI locally otherwise, and this app never sends unscreened
//  audio to Apple, full stop. That's expected to be universally available
//  in practice (en-US on-device recognition has shipped since iOS 13),
//  not a real-world limitation.
//
//  Steps 1-5 of the plan were validated as a side pass alongside the old
//  live-streaming request before this file replaced it outright -- see
//  git history on phiBranch for that incremental build/validation trail,
//  and docs/phi-hardening-plan.md for the full pipeline writeup.
//

import Foundation
import Combine
import AVFoundation
import Speech

/// Publishes dictation state for a single dictation session at a time.
/// `sessionTranscript` only ever reflects the *final*, fully-redacted
/// result of the pipeline described in the type header -- it resets to ""
/// each time `startDictation()` is called, and stays "" until the whole
/// pipeline completes (there is no live partial transcript by design).
@MainActor
final class SpeechRecognitionService: ObservableObject {
    enum ServiceError: LocalizedError, Equatable {
        case notAuthorized
        case recognizerUnavailable
        case microphoneUnavailable
        case audioSessionFailure
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "M & M Coach needs microphone and speech recognition access to dictate. You can enable this in Settings, or type the case instead."
            case .recognizerUnavailable:
                return "Dictation isn't available on this device right now. You can type the case instead."
            case .microphoneUnavailable:
                return "No microphone input is available. If you're using the simulator, enable Mac microphone input for the simulator, or run on a physical device."
            case .audioSessionFailure:
                return "Dictation couldn't start. Please try again."
            case .recognitionFailed:
                return "Dictation stopped before speech could be transcribed. Please try again, or type the case instead."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var sessionTranscript = ""
    @Published private(set) var error: ServiceError?

    /// The only recognizer this service uses -- on-device only, for both
    /// the PHI scan and (implicitly, since redacted audio is what actually
    /// gets uploaded) gating whether dictation is offered at all. See type
    /// header for why there is no separate server-based live recognizer
    /// anymore.
    private let onDeviceRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private let medicalDictionary: MedicalDictionaryService

    private var recordingFile: AVAudioFile?
    private var recordingFileURL: URL?
    private var onDeviceRecognitionTask: SFSpeechRecognitionTask?
    private var reTranscribeTask: SFSpeechRecognitionTask?
    /// Safety net for the whole post-recording pipeline (on-device scan ->
    /// redact -> re-transcribe -> splice/re-screen): if it hasn't produced
    /// a result within this window (a hung network call during
    /// re-transcribe is the realistic cause), finalize with whatever's
    /// available rather than leaving the UI waiting indefinitely. Much
    /// longer than the old live-streaming design's fallback needed to be,
    /// since this pipeline does real network + on-device work
    /// sequentially, entirely after the trainee has already stopped
    /// talking, rather than mostly during their speech.
    private var pipelineFallbackTask: Task<Void, Never>?
    /// Set as soon as the on-device scan (step 1 of the post-recording
    /// pipeline) succeeds. The fallback timer's -- and any later stage's
    /// failure path's -- best-effort text if a later network stage never
    /// completes: still fully PHI-screened (via PHIFilterService, text-
    /// based), just not upgraded with contextualStrings-boosted jargon
    /// accuracy from the redacted-audio re-transcribe.
    private var lastOnDeviceTranscript: String?

    /// `medicalDictionary` determines which specialty's terms seed
    /// contextualStrings for the re-transcribe pass (see
    /// `reTranscribeRedactedAudio`) -- callers should pass the same
    /// instance their DictationController resolved from the current
    /// SpecialtyStore selection, so recognition and correction stay
    /// consistent within one session.
    init(medicalDictionary: MedicalDictionaryService? = nil) {
        self.medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
    }

    func startDictation() async {
        guard !isRecording else { return }
        error = nil
        sessionTranscript = ""
        lastOnDeviceTranscript = nil

        guard await requestAuthorization() else {
            error = .notAuthorized
            return
        }
        guard let onDeviceRecognizer, onDeviceRecognizer.supportsOnDeviceRecognition, onDeviceRecognizer.isAvailable else {
            // No safe way to screen audio for PHI locally -- see type
            // header. Dictation is refused outright rather than falling
            // back to sending unscreened audio anywhere.
            error = .recognizerUnavailable
            return
        }

        onDeviceRecognitionTask?.cancel()
        onDeviceRecognitionTask = nil
        reTranscribeTask?.cancel()
        reTranscribeTask = nil
        pipelineFallbackTask?.cancel()
        pipelineFallbackTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = .audioSessionFailure
            return
        }
        guard audioSession.isInputAvailable else {
            self.error = .microphoneUnavailable
            teardownAudioSession()
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            self.error = .microphoneUnavailable
            teardownAudioSession()
            return
        }
        openRecordingFile(format: recordingFormat)
        guard recordingFile != nil else {
            // Nothing to screen/redact if the local capture itself never
            // opened -- unlike the old design, this file is now
            // load-bearing, not optional scaffolding.
            self.error = .audioSessionFailure
            teardownAudioSession()
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            try? self?.recordingFile?.write(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = .audioSessionFailure
            teardownAudioSession()
            discardRecordingFile()
            return
        }

        isRecording = true
    }

    /// Stops capturing audio right away, but deliberately does NOT flip
    /// `isRecording` to false yet -- the post-recording pipeline (on-device
    /// scan -> redact -> re-transcribe -> splice/re-screen, see type
    /// header) still has to run and produce the definitive final text.
    /// Callers that need that text should wait for `isRecording` to go
    /// false rather than reading `sessionTranscript` immediately here.
    func stopDictation() {
        guard isRecording else { return }
        audioEngine.stop()
        teardownAudioSession()
        scheduleFinalizationFallback()
        finalizeRecordingFile()
    }

    /// If the post-recording pipeline never completes within a generous
    /// window (a hung network call during re-transcribe is the realistic
    /// cause), finalize with the best text available rather than leaving
    /// `isRecording` stuck true and the UI waiting forever. Uses the
    /// on-device transcript (still fully PHI-screened as text, just
    /// without the redacted-audio re-transcribe's jargon-accuracy
    /// upgrade) if the scan got that far; otherwise there's nothing usable
    /// to fall back to.
    private func scheduleFinalizationFallback() {
        pipelineFallbackTask?.cancel()
        pipelineFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, !Task.isCancelled, self.isRecording else { return }
            #if DEBUG
            print("[SpeechRecognitionService] pipeline fallback fired -- a later stage never completed in time")
            #endif
            if let transcript = self.lastOnDeviceTranscript {
                self.finishDictation(text: PHIFilterService.shared.redact(transcript).redactedText)
            } else {
                self.failDictation()
            }
        }
    }

    /// Sets the session's final, fully-redacted text and marks the session
    /// done. The one place `isRecording` becomes false on a successful
    /// path -- see type header for why callers should treat that as the
    /// signal the text is ready, not any earlier point in the pipeline.
    private func finishDictation(text: String) {
        guard isRecording else { return }
        pipelineFallbackTask?.cancel()
        pipelineFallbackTask = nil
        // .cancel() even on the success path -- if this is the task whose
        // own completion is calling in right now, it has already delivered
        // its final result, so cancelling is a harmless no-op; if this is
        // the OTHER task (e.g. the fallback timer finalized early using
        // lastOnDeviceTranscript while re-transcribe was still hanging),
        // this actually stops the now-pointless work rather than letting
        // it run to completion in the background for a result nothing
        // will read.
        onDeviceRecognitionTask?.cancel()
        onDeviceRecognitionTask = nil
        reTranscribeTask?.cancel()
        reTranscribeTask = nil
        sessionTranscript = text
        isRecording = false
    }

    private func failDictation() {
        // SFSpeechRecognitionTask's completion handler can fire more than
        // once under an interruption (confirmed on real hardware: toggling
        // airplane mode mid-pipeline produced a partial result, then a
        // "final" empty one, then a THIRD callback reporting cancellation)
        // -- without this guard, that late callback overwrote an already-
        // finalized session's state with an error after the pipeline had
        // already completed (via the on-device-transcript fallback) with
        // whatever it had. Mirrors the same guard finishDictation(text:)
        // already has.
        guard isRecording else { return }
        pipelineFallbackTask?.cancel()
        pipelineFallbackTask = nil
        onDeviceRecognitionTask?.cancel()
        onDeviceRecognitionTask = nil
        reTranscribeTask?.cancel()
        reTranscribeTask = nil
        isRecording = false
        error = .recognitionFailed
    }

    /// Opens a fresh temp file for this session's raw audio capture. Also
    /// sweeps any file left behind by a prior session that didn't get to
    /// clean up after itself (e.g. a crash) -- this is raw, unredacted
    /// audio, so it shouldn't linger on disk longer than the session that
    /// produced it.
    private func openRecordingFile(format: AVAudioFormat) {
        Self.removeStaleRecordingFiles()

        let url = Self.makeRecordingFileURL()
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingFileURL = url
        } catch {
            recordingFile = nil
            recordingFileURL = nil
        }
    }

    /// Discards the session's recording file without processing it --
    /// used only when capture itself failed before `isRecording` ever
    /// became true (there's no real dictation to run the pipeline on).
    private func discardRecordingFile() {
        recordingFile = nil
        if let url = recordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileURL = nil
    }

    /// Closes (flushing) the session's recording file and kicks off the
    /// post-recording pipeline (`runOnDeviceScan`) -- the file is deleted
    /// once that pipeline is done with it, not here.
    private func finalizeRecordingFile() {
        recordingFile = nil
        guard let url = recordingFileURL else {
            failDictation() // nothing was ever captured to process
            return
        }
        recordingFileURL = nil

        #if DEBUG
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        print("[SpeechRecognitionService] captured \(bytes ?? -1) bytes of session audio")
        #endif

        runOnDeviceScan(fileURL: url)
    }

    /// Pipeline stage 1: on-device-only recognition of the just-recorded
    /// file (never touches the network) so PHIFilterService has a
    /// transcript to screen. On success, hands off to
    /// `redactAndReTranscribe`. On failure (e.g. the trainee said
    /// nothing), there is nothing usable to fall back to -- fails the
    /// whole session.
    private func runOnDeviceScan(fileURL: URL) {
        guard let onDeviceRecognizer, onDeviceRecognizer.supportsOnDeviceRecognition, onDeviceRecognizer.isAvailable else {
            // Already checked in startDictation(); re-checked because
            // availability could theoretically change mid-session.
            try? FileManager.default.removeItem(at: fileURL)
            failDictation()
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.shouldReportPartialResults = false

        onDeviceRecognitionTask = onDeviceRecognizer.recognitionTask(with: request) { [weak self] result, taskError in
            #if DEBUG
            print("[SpeechRecognitionService] on-device scan callback: error=\(String(describing: taskError)) isFinal=\(result?.isFinal ?? false) text=\(result?.bestTranscription.formattedString ?? "nil")")
            #endif
            // A "final" result can still be empty -- confirmed on real
            // hardware under an interruption (airplane mode mid-pipeline
            // produced isFinal=true with no text), which must NOT be
            // treated as "recognized successfully, transcript happens to
            // be empty": that let garbage flow into the redact/re-transcribe
            // pipeline. Unlike here, an empty RE-TRANSCRIBE result later
            // in the pipeline is legitimate (the whole utterance being
            // redacted PHI produces a genuinely empty base transcript) --
            // this stricter check only applies to this first, raw pass.
            // Checked against a TRIMMED copy only -- the untrimmed string
            // is what's actually used downstream, since segment character
            // ranges are computed by the Speech framework against it, and
            // trimming would silently shift every later range lookup.
            let isEmpty = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            guard taskError == nil, let result, result.isFinal, !isEmpty else {
                try? FileManager.default.removeItem(at: fileURL)
                Task { @MainActor in self?.failDictation() }
                return
            }
            let transcript = result.bestTranscription.formattedString
            let segments = result.bestTranscription.segments
            Task { @MainActor in
                self?.lastOnDeviceTranscript = transcript
                self?.redactAndReTranscribe(sourceURL: fileURL, transcript: transcript, segments: segments)
            }
        }
    }

    /// Pipeline stages 2-3: computes redaction spans from the on-device
    /// transcript's PHI findings, mutes the audio, then uploads the
    /// REDACTED file (never the original) to the server-based recognizer
    /// -- contextualStrings still active -- for the real, jargon-accurate
    /// transcript. `redactAudio` below runs synchronously on the main
    /// actor -- a deliberate tradeoff, not an oversight: it's chunked file
    /// I/O over a few MB at most for a realistic dictation segment (fast
    /// on-device), the pipeline's actual latency is dominated by the
    /// network calls on either side of it, and the UI is already showing a
    /// wait state for the whole pipeline regardless. Revisit only if
    /// real-device profiling shows otherwise. If redaction or the
    /// re-transcribe upload can't run at all, falls back to the on-device
    /// transcript (text-redacted) rather than losing the dictation
    /// outright.
    private func redactAndReTranscribe(sourceURL: URL, transcript: String, segments: [SFTranscriptionSegment]) {
        let located = PHIFilterService.shared.find(in: transcript)
        // SFTranscriptionSegment.substringRange is an NSRange (UTF-16
        // indexed), not a Range<String.Index> -- convert against the same
        // transcript it came from. Ranges/segments that fail to convert
        // (should not happen in practice, since they're both derived from
        // the same string) are skipped rather than crashing.
        let taggedRanges: [(range: Range<String.Index>, tag: PHIFinding.Category)] = located.compactMap {
            guard let range = Range($0.range, in: transcript) else { return nil }
            return (range, $0.category)
        }
        let recognizedSegments = segments.compactMap { segment -> RecognizedSegment? in
            guard let range = Range(segment.substringRange, in: transcript) else { return nil }
            return RecognizedSegment(range: range, timestamp: segment.timestamp, duration: segment.duration)
        }
        let audioDuration = recognizedSegments.map(\.end).max() ?? .infinity
        let spans = AudioRedactionService.redactionSpans(for: taggedRanges, segments: recognizedSegments, audioDuration: audioDuration)

        #if DEBUG
        print("[SpeechRecognitionService] \(located.count) finding(s) -> \(spans.count) redaction span(s): \(spans.map(\.span))")
        #endif

        let redactedURL = sourceURL.deletingPathExtension().appendingPathExtension("redacted.caf")
        do {
            try AudioRedactionService.redactAudio(sourceURL: sourceURL, destinationURL: redactedURL, spans: spans.map(\.span))
        } catch {
            #if DEBUG
            print("[SpeechRecognitionService] redactAudio failed: \(error) -- falling back to on-device transcript")
            #endif
            try? FileManager.default.removeItem(at: sourceURL)
            finishDictation(text: PHIFilterService.shared.redact(transcript).redactedText)
            return
        }
        try? FileManager.default.removeItem(at: sourceURL) // superseded by the redacted copy

        guard let onDeviceRecognizer, onDeviceRecognizer.isAvailable else {
            #if DEBUG
            print("[SpeechRecognitionService] recognizer unavailable for re-transcribe -- falling back to on-device transcript")
            #endif
            try? FileManager.default.removeItem(at: redactedURL)
            finishDictation(text: PHIFilterService.shared.redact(transcript).redactedText)
            return
        }

        let reTranscribeRequest = SFSpeechURLRecognitionRequest(url: redactedURL)
        reTranscribeRequest.taskHint = .dictation
        reTranscribeRequest.shouldReportPartialResults = false
        // Server-based (requiresOnDeviceRecognition left unset) so
        // contextualStrings actually has an effect when the network is
        // available -- confirmed on real hardware that when it isn't,
        // SFSpeechRecognizer silently falls back to on-device for this
        // request too (taskError stays nil, isFinal still fires normally)
        // rather than erroring -- contextualStrings just has no effect for
        // that call, same as if it had been requested on-device directly.
        // The explicit `taskError != nil` fallback just below this still
        // matters for a genuine failure (e.g. a request that reaches the
        // server but the server errors), not for "offline" specifically.
        // The audio it receives has already had every flagged span muted.
        reTranscribeRequest.contextualStrings = medicalDictionary.contextualStringSeed

        reTranscribeTask = onDeviceRecognizer.recognitionTask(with: reTranscribeRequest) { [weak self] result, taskError in
            #if DEBUG
            print("[SpeechRecognitionService] re-transcribe callback: error=\(String(describing: taskError)) isFinal=\(result?.isFinal ?? false) text=\(result?.bestTranscription.formattedString ?? "nil")")
            #endif
            if taskError != nil || result?.isFinal == true {
                try? FileManager.default.removeItem(at: redactedURL)
            }
            guard taskError == nil, let result, result.isFinal else {
                if taskError != nil {
                    Task { @MainActor in
                        self?.finishDictation(text: PHIFilterService.shared.redact(transcript).redactedText)
                    }
                }
                return
            }
            Task { @MainActor in
                let final = Self.splicedAndReScreened(reTranscribedResult: result, spans: spans)
                self?.finishDictation(text: final)
            }
        }
    }

    /// Pipeline stages 4-5: inserts a category-labeled placeholder into
    /// the re-transcribed text at each redaction span's position (safe to
    /// align by time against spans computed from the ORIGINAL audio's
    /// timing -- `redactAudio` mutes samples in place, so the redacted
    /// file has the same length/timeline as the source), then re-runs the
    /// existing text-based `PHIFilterService` on the spliced result as a
    /// defense-in-depth pass -- catches anything the on-device scan
    /// missed (e.g. a name garbled badly enough that it no longer reads
    /// as one).
    private static func splicedAndReScreened(reTranscribedResult: SFSpeechRecognitionResult, spans: [AudioRedactionService.TaggedRedactionSpan<PHIFinding.Category>]) -> String {
        let reTranscript = reTranscribedResult.bestTranscription.formattedString
        let reSegments = reTranscribedResult.bestTranscription.segments.compactMap { segment -> RecognizedSegment? in
            guard let range = Range(segment.substringRange, in: reTranscript) else { return nil }
            return RecognizedSegment(range: range, timestamp: segment.timestamp, duration: segment.duration)
        }

        let spliced = AudioRedactionService.splicePlaceholders(
            into: reTranscript,
            segments: reSegments,
            spans: spans,
            placeholder: PHIFinding.Category.combinedPlaceholder
        )

        let reScreenResult = PHIFilterService.shared.redact(spliced)
        let final = reScreenResult.hasFindings ? reScreenResult.redactedText : spliced

        #if DEBUG
        print("[SpeechRecognitionService] spliced transcript = \"\(spliced)\"")
        if reScreenResult.hasFindings {
            print("[SpeechRecognitionService] re-screen caught \(reScreenResult.findings.count) more finding(s) the on-device scan missed")
        }
        print("[SpeechRecognitionService] FINAL text = \"\(final)\"")
        #endif

        return final
    }

    private static let recordingFilePrefix = "mmcoach-dictation-"

    private static func makeRecordingFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(recordingFilePrefix + UUID().uuidString)
            .appendingPathExtension("caf")
    }

    private static func removeStaleRecordingFiles() {
        let directory = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix(recordingFilePrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func teardownAudioSession() {
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
