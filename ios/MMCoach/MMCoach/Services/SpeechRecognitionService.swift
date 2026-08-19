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
                return "MMCoach needs microphone and speech recognition access to dictate. You can enable this in Settings, or type the case instead."
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
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = .audioSessionFailure
            teardownAudioSession()
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
