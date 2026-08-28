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
//  Nothing reads that file yet; it's deleted the moment the session ends,
//  purely to prove the capture plumbing before any later step depends on
//  it. This does not change what's sent to Apple's servers.
//
//  Step 2 of that same plan: a second, on-device-only recognition request
//  (`onDeviceRecognitionRequest`/`onDeviceRecognitionTask`) runs in parallel
//  on the same audio, purely to see what PHIFilterService would flag in its
//  transcript -- logged, never acted on. This is still detect-only: no
//  audio is muted, nothing about the primary (server-based) transcript or
//  what reaches Apple changes. It's how detection quality gets validated
//  against real speech before redaction (a later step) becomes load-bearing.
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
    private let audioEngine = AVAudioEngine()
    private let medicalDictionary: MedicalDictionaryService
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Detect-only PHI scan pass -- see the type header's "Step 2" note.
    /// `nil` whenever no session is recording, or if on-device recognition
    /// isn't available on this device/locale (in which case the session
    /// proceeds exactly as it does today, just without this side channel).
    private var onDeviceRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
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

        // Step 2's detect-only side channel -- see type header. `nil` (and
        // simply not fed audio below) if this device/locale can't do
        // on-device recognition at all.
        let onDeviceRequest: SFSpeechAudioBufferRecognitionRequest?
        #if DEBUG
        print("[SpeechRecognitionService] supportsOnDeviceRecognition = \(recognizer.supportsOnDeviceRecognition)")
        #endif
        if recognizer.supportsOnDeviceRecognition {
            let scanRequest = SFSpeechAudioBufferRecognitionRequest()
            scanRequest.shouldReportPartialResults = false
            scanRequest.requiresOnDeviceRecognition = true
            onDeviceRequest = scanRequest
            onDeviceRecognitionRequest = scanRequest
        } else {
            onDeviceRequest = nil
            onDeviceRecognitionRequest = nil
        }

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
            onDeviceRequest?.append(buffer)
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

        if let onDeviceRequest {
            #if DEBUG
            print("[SpeechRecognitionService] on-device scan task starting")
            #endif
            onDeviceRecognitionTask = recognizer.recognitionTask(with: onDeviceRequest) { [weak self] result, taskError in
                #if DEBUG
                print("[SpeechRecognitionService] on-device scan callback: error=\(String(describing: taskError)) isFinal=\(result?.isFinal ?? false) text=\(result?.bestTranscription.formattedString ?? "nil")")
                #endif
                guard taskError == nil, let result, result.isFinal else { return }
                Task { @MainActor in
                    self?.logPHIScan(transcript: result.bestTranscription.formattedString)
                }
            }
        } else {
            #if DEBUG
            print("[SpeechRecognitionService] on-device scan skipped -- not supported on this device/locale")
            #endif
        }
    }

    /// Detect-only: runs the existing text-based PHI filter over the
    /// on-device transcript and logs what it found. Never touches
    /// `sessionTranscript`, never redacts anything, never blocks or delays
    /// the primary (server-based) dictation flow -- see type header "Step 2".
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
        onDeviceRecognitionRequest?.endAudio()
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
        onDeviceRecognitionRequest?.endAudio()
        onDeviceRecognitionTask?.finish()
        onDeviceRecognitionTask = nil
        onDeviceRecognitionRequest = nil
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
        onDeviceRecognitionTask?.cancel()
        onDeviceRecognitionTask = nil
        onDeviceRecognitionRequest = nil
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

    /// Releases (closing/flushing) and deletes the session's recording
    /// file. Nothing reads it yet, so it's removed immediately rather than
    /// kept around -- a later pipeline step will change this once a
    /// redaction pass actually consumes the file before it's deleted.
    private func finalizeRecordingFile() {
        recordingFile = nil
        if let url = recordingFileURL {
            #if DEBUG
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
            print("[SpeechRecognitionService] captured \(bytes ?? -1) bytes of session audio (discarded -- step 1 capture-only)")
            #endif
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileURL = nil
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
