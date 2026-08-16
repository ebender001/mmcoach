//
//  SpeechRecognitionService.swift
//  MMCoach
//
//  Owns on-device speech recognition for dictating a case narrative.
//  Nothing outside this file talks to Speech/AVFoundation directly.
//
//  Only the recognized TEXT ever leaves this service -- audio is never
//  sent anywhere, including to the MMCoach backend.
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
        case audioSessionFailure

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "MMCoach needs microphone and speech recognition access to dictate. You can enable this in Settings, or type the case instead."
            case .recognizerUnavailable:
                return "Dictation isn't available right now. You can type the case instead."
            case .audioSessionFailure:
                return "Dictation couldn't start. Please try again."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var sessionTranscript = ""
    @Published private(set) var error: ServiceError?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

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

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = .audioSessionFailure
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
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
                if taskError != nil || (result?.isFinal ?? false) {
                    self.stopDictation()
                }
            }
        }
    }

    func stopDictation() {
        guard isRecording else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        teardownAudioSession()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
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
