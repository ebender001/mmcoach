//
//  SpeechRecognitionService.swift
//  MMCoach
//
//  Owns speech recognition for dictating a case narrative. Nothing outside
//  this file talks to Speech/AVFoundation directly.
//
//  Only the recognized TEXT ever leaves this service for the MMCoach
//  backend. Recognition itself is *not* pinned to on-device: server-based
//  recognition is allowed so `contextualStrings` vocabulary boosting takes
//  effect (Apple's on-device recognizer ignores contextualStrings entirely).
//  That means audio for a dictation session may be sent to Apple's speech
//  recognition servers when the network is available; SFSpeechRecognizer
//  falls back to on-device automatically when it isn't.
//
//  Each session's raw audio is also captured to a private temp file (see
//  `recordingFile`/`finalizeRecordingFile()`) -- step 1 of the record ->
//  redact -> send PHI-hardening pipeline in docs/phi-hardening-plan.md.
//
//  Step 2 of that plan: once the primary (server-based) task has finished
//  for the session, a SEQUENTIAL on-device-only pass re-recognizes the
//  just-recorded file (SFSpeechURLRecognitionRequest, requiresOnDeviceRecognition
//  = true) purely to see what PHIFilterService would flag in its transcript
//  -- logged, never acted on. This runs strictly AFTER the primary task,
//  not concurrently with it: empirically, this device can't run two
//  SFSpeechRecognitionTasks against live microphone audio at the same
//  time (every attempt at running them in parallel failed instantly with
//  "No speech detected", regardless of recognizer instance, request
//  config, or whether the two tasks shared the same AVAudioPCMBuffer
//  objects -- the identical on-device request succeeded immediately once
//  nothing else was actively consuming live audio at the same time). This
//  is still detect-only: no audio is muted, nothing about the primary
//  transcript or what already reached Apple's servers changes. It's how
//  detection quality gets validated against real speech before redaction
//  (a later step) becomes load-bearing, and the file-based request pattern
//  here is the same one step 6 (server-based transcription of the redacted
//  file) will reuse later.
//

import Foundation
import Combine
import AVFoundation
import Speech

/// Publishes live dictation state for a single dictation session at a
/// time. `sessionTranscript` reflects only the *current* recording
/// session (it resets to "" each time `startDictation()` is called);
/// merging it with previously-entered text is the caller's job, since
/// this service has no opinion about what the trainee already typed.
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
                return "Dictation isn't available right now. You can type the case instead."
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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// A separate `SFSpeechRecognizer` instance for the step-2 on-device
    /// scan pass, isolated from the primary task's recognizer. Not required
    /// for correctness now that the scan runs sequentially rather than
    /// concurrently (see type header), but kept for cleanliness -- no
    /// reason to route an unrelated pass through the same instance.
    private let onDeviceRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private let medicalDictionary: MedicalDictionaryService
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// The step-2 on-device scan's task -- see type header. Only ever
    /// active after the session has already ended (finalizeRecordingFile()),
    /// never during live recording.
    private var onDeviceRecognitionTask: SFSpeechRecognitionTask?
    /// Local capture of the current session's raw audio -- see the type
    /// header comment. `nil` whenever no session is recording, or if the
    /// file couldn't be opened (capture failure never blocks dictation
    /// itself, since nothing depends on this file yet).
    private var recordingFile: AVAudioFile?
    private var recordingFileURL: URL?
    /// Safety net for stopDictation(): if the recognizer never delivers a
    /// final result after endAudio() (e.g. a hung connection), this forces
    /// finalization so the UI doesn't wait forever.
    private var finalizationFallbackTask: Task<Void, Never>?

    /// `medicalDictionary` determines which specialty's terms seed
    /// contextualStrings (see startDictation()) -- callers should pass the
    /// same instance their DictationController resolved from the current
    /// SpecialtyStore selection, so recognition and correction stay
    /// consistent within one session.
    init(medicalDictionary: MedicalDictionaryService? = nil) {
        self.medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
    }

    func startDictation() async {
        guard !isRecording else { return }
        error = nil
        sessionTranscript = ""

        guard await requestAuthorization() else {
            error = .notAuthorized
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = .recognizerUnavailable
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        finalizationFallbackTask?.cancel()
        finalizationFallbackTask = nil

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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Left unset (server-based when the network allows it) so
        // contextualStrings below actually has an effect -- see header comment.
        request.contextualStrings = medicalDictionary.contextualStringSeed
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            self.error = .microphoneUnavailable
            teardownAudioSession()
            return
        }
        openRecordingFile(format: recordingFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            try? self?.recordingFile?.write(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = .audioSessionFailure
            teardownAudioSession()
            finalizeRecordingFile()
            return
        }

        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.sessionTranscript = result.bestTranscription.formattedString
                }
                if taskError != nil {
                    self.failDictation()
                } else if result?.isFinal ?? false {
                    self.finishDictation()
                }
            }
        }
    }

    /// Detect-only: runs the existing text-based PHI filter over the
    /// on-device transcript and logs what it found. Never touches
    /// `sessionTranscript`, never redacts anything -- see type header "Step 2".
    private func logPHIScan(transcript: String) {
        #if DEBUG
        let result = PHIFilterService.shared.redact(transcript)
        if result.hasFindings {
            let summary = result.findings.map { "\($0.category.rawValue): \"\($0.originalText)\"" }.joined(separator: ", ")
            print("[SpeechRecognitionService] on-device PHI scan would redact \(result.findings.count) item(s): \(summary)")
        } else {
            print("[SpeechRecognitionService] on-device PHI scan found nothing to redact")
        }
        print("[SpeechRecognitionService] on-device transcript was: \"\(transcript)\"")
        #endif
    }

    /// Stops capturing audio right away, but deliberately does NOT flip
    /// `isRecording` to false yet. `sessionTranscript` may still be an
    /// interim result at this point -- the recognizer delivers the true
    /// final transcript asynchronously after `endAudio()`, via the
    /// `isFinal` branch below, which is what actually calls
    /// `finishDictation()`. Callers that need the definitive final text
    /// (not just "user tapped stop") should wait for `isRecording` to go
    /// false rather than reading `sessionTranscript` immediately here.
    func stopDictation() {
        guard isRecording else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        teardownAudioSession()
        scheduleFinalizationFallback()
    }

    /// If the recognizer never delivers a final result after endAudio()
    /// (e.g. a hung network connection), force finalization anyway using
    /// whatever `sessionTranscript` currently holds, rather than leaving
    /// `isRecording` stuck true and the UI waiting forever.
    private func scheduleFinalizationFallback() {
        finalizationFallbackTask?.cancel()
        finalizationFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.finishDictation()
        }
    }

    private func finishDictation() {
        guard isRecording else { return }
        finalizationFallbackTask?.cancel()
        finalizationFallbackTask = nil
        audioEngine.stop()
        recognitionRequest?.endAudio()
        teardownAudioSession()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        finalizeRecordingFile()
    }

    private func failDictation() {
        finalizationFallbackTask?.cancel()
        finalizationFallbackTask = nil
        audioEngine.stop()
        teardownAudioSession()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        error = .recognitionFailed
        finalizeRecordingFile()
    }

    /// Opens a fresh temp file for this session's raw audio capture (step 1
    /// of the PHI-hardening pipeline -- see the type header). Also sweeps
    /// any file left behind by a prior session that didn't get to clean up
    /// after itself (e.g. a crash) -- this is raw, unredacted audio, so it
    /// shouldn't linger on disk longer than the session that produced it.
    /// Failing to open the file is non-fatal: dictation proceeds exactly as
    /// before, just without a local capture, since nothing depends on it yet.
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

    /// Closes (flushing) the session's recording file, then hands it to the
    /// step-2 on-device scan (see `runSequentialOnDeviceScan`), which
    /// deletes it once done. If the scan can't run at all (unsupported
    /// device/locale), the file is deleted immediately instead -- nothing
    /// reads it in that case, so it shouldn't linger on disk.
    private func finalizeRecordingFile() {
        recordingFile = nil
        guard let url = recordingFileURL else { return }
        recordingFileURL = nil

        #if DEBUG
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        print("[SpeechRecognitionService] captured \(bytes ?? -1) bytes of session audio")
        #endif

        runSequentialOnDeviceScan(fileURL: url)
    }

    /// Step 2's on-device PHI scan, run as a sequential pass over the
    /// just-recorded file -- always AFTER the primary task has already
    /// finished, never concurrently with it (see type header for why).
    /// Detect-only: logs what PHIFilterService would flag, mutes nothing,
    /// changes nothing about what already reached Apple's servers via the
    /// primary task. Deletes `fileURL` once the pass completes, whether it
    /// succeeded or not -- this is still scaffolding, nothing else reads it.
    private func runSequentialOnDeviceScan(fileURL: URL) {
        guard let onDeviceRecognizer, onDeviceRecognizer.supportsOnDeviceRecognition, onDeviceRecognizer.isAvailable else {
            #if DEBUG
            print("[SpeechRecognitionService] on-device scan skipped -- not supported on this device/locale")
            #endif
            try? FileManager.default.removeItem(at: fileURL)
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
            if let result, taskError == nil {
                Task { @MainActor in
                    self?.logPHIScan(transcript: result.bestTranscription.formattedString)
                }
            }
            if taskError != nil || result?.isFinal == true {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
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
