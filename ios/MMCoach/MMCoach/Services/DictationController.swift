//
//  DictationController.swift
//  MMCoach
//
//  Shared dictation lifecycle: mic capture -> wait for the true final
//  transcript -> cloud terminology correction (falling back to on-device
//  correction if the network call fails) -> hand the result back to the
//  owner. Used identically by the initial case narrative (NewCaseViewModel)
//  and interview-answer (CaseInterviewViewModel) dictation flows -- see
//  DictationEditorView for the matching shared UI.
//
//  The owner keeps ownership of its own text property (and whatever
//  validation/side effects it attaches to changing it, e.g. spell-check
//  flagging) and is notified via `onCorrectedText` once a session's result
//  is ready to append.
//

import Foundation
import Combine

/// The dictation lifecycle for a single mic-button session. Driving the UI
/// off one enum (rather than several independent booleans) keeps the mic
/// button/overlay/submit button impossible to get into an inconsistent
/// combination of states.
enum DictationPhase: Equatable {
    /// Not dictating. The editor is interactive.
    case idle
    /// Actively capturing audio.
    case listening
    /// User tapped stop; waiting for the recognizer's true final transcript
    /// (may still be finalizing the last word or two server-side).
    case finishingUp
    /// Sending the finished segment to the backend for terminology
    /// correction before it's appended to the text.
    case correcting
}

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var dictationPhase: DictationPhase = .idle
    @Published var dictationErrorMessage: String?
    /// Set whenever PHIFilterService actually redacted something from a
    /// just-finished segment, so the trainee can be told what was removed
    /// and why. Always runs on-device, before the segment goes anywhere.
    @Published var phiNoticeMessage: String?

    var isDictating: Bool { dictationPhase != .idle }

    /// Called once a session's dictated segment has been finalized and
    /// corrected (or locally corrected, if the cloud call failed) with the
    /// full text that should replace the owner's current text. The owner
    /// is responsible for assigning this to its own @Published property.
    var onCorrectedText: ((String) -> Void)?

    let speechService: SpeechRecognitionService

    private let medicalDictionary: MedicalDictionaryService
    private let phiFilter: PHIFilterService
    private var textBeforeDictation = ""
    /// The current dictation session's live transcript. Deliberately not
    /// surfaced to the owner as it streams in -- an in-progress
    /// misrecognition flickering into view is distracting, and correction
    /// needs the session's transcript to be complete before it can run.
    private var pendingSessionTranscript = ""
    private var observationTasks: [Task<Void, Never>] = []

    init(speechService: SpeechRecognitionService? = nil,
         medicalDictionary: MedicalDictionaryService? = nil,
         phiFilter: PHIFilterService? = nil) {
        let medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
        self.medicalDictionary = medicalDictionary
        self.phiFilter = phiFilter ?? .shared
        self.speechService = speechService ?? SpeechRecognitionService(medicalDictionary: medicalDictionary)
        observeSpeechService()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    /// Starts or stops dictation. `currentText` is the owner's text at the
    /// moment dictation starts -- the newly dictated segment is appended to
    /// it, never overwriting.
    func toggleDictation(currentText: String) async {
        switch dictationPhase {
        case .idle:
            textBeforeDictation = currentText
            dictationPhase = .listening
            await speechService.startDictation()
            if !speechService.isRecording {
                // startDictation failed (auth denied, no mic, etc.) --
                // speechService.error is surfaced separately via errorTask.
                dictationPhase = .idle
            }
        case .listening:
            dictationPhase = .finishingUp
            speechService.stopDictation()
        case .finishingUp, .correcting:
            break
        }
    }

    private static func merge(base: String, sessionText: String) -> String {
        guard !sessionText.isEmpty else { return base }
        return base.isEmpty ? sessionText : base + " " + sessionText
    }

    private func observeSpeechService() {
        let transcriptTask = Task { [weak self] in
            guard let self else { return }
            for await sessionText in self.speechService.$sessionTranscript.values {
                self.pendingSessionTranscript = sessionText
            }
        }
        let recordingTask = Task { [weak self] in
            guard let self else { return }
            for await recording in self.speechService.$isRecording.values {
                guard !recording else { continue }
                switch self.dictationPhase {
                case .finishingUp:
                    self.dictationPhase = .correcting
                    await self.finalizeDictation()
                case .listening:
                    // Recognition stopped on its own (e.g. a dropped
                    // connection) rather than via the user tapping stop.
                    // Salvage whatever was captured with a local-only
                    // correction pass rather than losing it outright.
                    // PHI screening still runs even on this path: the
                    // result still ends up in text that later goes to the
                    // cloud via submit(), just not on this codepath itself.
                    let phiResult = self.phiFilter.redact(self.pendingSessionTranscript)
                    if phiResult.hasFindings {
                        self.phiNoticeMessage = phiResult.noticeMessage
                    }
                    self.onCorrectedText?(self.medicalDictionary.correctedTranscript(
                        Self.merge(base: self.textBeforeDictation, sessionText: phiResult.redactedText)
                    ))
                    self.dictationPhase = .idle
                case .idle, .correcting:
                    break
                }
            }
        }
        let errorTask = Task { [weak self] in
            guard let self else { return }
            for await dictationError in self.speechService.$error.values {
                self.dictationErrorMessage = dictationError?.errorDescription
            }
        }
        observationTasks = [transcriptTask, recordingTask, errorTask]
    }

    private func finalizeDictation() async {
        let rawSegment = pendingSessionTranscript
        guard !rawSegment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dictationPhase = .idle
            return
        }

        // PHI screening happens here, on-device, BEFORE anything is sent
        // to correctDictation's cloud call below -- never after. Only the
        // already-redacted text ever reaches the network. `textBeforeDictation`
        // is screened too, not just the new segment: it may contain PHI the
        // trainee typed by hand earlier in this session, which wouldn't
        // have passed through this filter yet.
        let priorResult = phiFilter.redact(textBeforeDictation)
        let segmentResult = phiFilter.redact(rawSegment)
        let priorText = priorResult.redactedText
        let segment = segmentResult.redactedText
        if priorResult.hasFindings || segmentResult.hasFindings {
            phiNoticeMessage = PHIFilterResult(redactedText: "", findings: priorResult.findings + segmentResult.findings).noticeMessage
        }

        do {
            let result = try await BackendService.correctDictation(priorNarrative: priorText, newSegment: segment)
            onCorrectedText?(Self.merge(base: priorText, sessionText: result.correctedSegment))
        } catch {
            onCorrectedText?(medicalDictionary.correctedTranscript(
                Self.merge(base: priorText, sessionText: segment)
            ))
            dictationErrorMessage = Self.dictationCorrectionFallbackMessage(for: error)
        }
        dictationPhase = .idle
    }

    /// `error` is whatever `BackendService.correctDictation` threw --
    /// always a `BackendError` in practice, since `BackendService.run(_:)`
    /// maps every failure to one before it ever reaches here. Distinguish
    /// the reason (dropped connection vs. a server/AI-provider problem vs.
    /// a malformed response) rather than always blaming "the server" --
    /// only the first of those is actually a connectivity issue.
    private static func dictationCorrectionFallbackMessage(for error: Error) -> String {
        let reason: String
        switch error as? BackendError {
        case .network:
            reason = "MMCoach couldn't reach the server to double-check medical terms."
        case .decoding:
            reason = "MMCoach couldn't read the server's response while checking medical terms."
        case .server, .invalidState, .notFound, .validation:
            reason = "The server couldn't check medical terms right now."
        case .sessionExpired:
            reason = "Your session expired, so medical terms couldn't be double-checked."
        case nil:
            reason = "MMCoach couldn't double-check medical terms right now."
        }
        return "\(reason) A quick on-device check was used instead."
    }
}
