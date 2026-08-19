//
//  CaseInterviewViewModel.swift
//  MMCoach
//
//  Owns the one-question-at-a-time interview loop. The client never
//  decides whether enough information has been collected -- it only
//  displays whatever `status`/`nextQuestion` the backend returns and
//  reacts to it.
//

import Foundation
import Combine

@MainActor
final class CaseInterviewViewModel: ObservableObject {
    let caseId: String

    @Published private(set) var status: CaseStatus
    @Published private(set) var currentQuestion: MMQuestion?
    @Published var answerText = "" {
        didSet {
            spellingSuggestions = medicalDictionary.possibleMisspellings(in: answerText)
        }
    }
    @Published private(set) var isLoadingCase: Bool
    @Published private(set) var isSubmittingAnswer = false
    @Published private(set) var isFinalizing = false
    @Published var errorMessage: String?
    @Published private(set) var spellingSuggestions: [String] = []
    /// Mirrors `dictation.dictationPhase`/`dictationErrorMessage`/
    /// `phiNoticeMessage` so the view only needs to observe this one
    /// object -- see observeDictation().
    @Published private(set) var dictationPhase: DictationPhase = .idle
    @Published var dictationErrorMessage: String?
    @Published var phiNoticeMessage: String?

    let dictation: DictationController

    private let store: RecentCasesStore
    private let medicalDictionary: MedicalDictionaryService
    private let phiFilter: PHIFilterService
    private var observationTasks: [Task<Void, Never>] = []

    var isDictating: Bool { dictationPhase != .idle }

    /// - Parameter initialCase: Pass the case snapshot already returned by
    ///   mmCreateCase/mmAnswerQuestion when navigating here right after
    ///   that call, so no extra network round trip is needed. Pass `nil`
    ///   when resuming an in-progress case from Home; the view model will
    ///   fetch current state via `loadIfNeeded()`.
    init(caseId: String,
         initialCase: MMCase?,
         store: RecentCasesStore? = nil,
         dictation: DictationController? = nil,
         medicalDictionary: MedicalDictionaryService? = nil,
         phiFilter: PHIFilterService? = nil) {
        let medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
        self.caseId = caseId
        self.store = store ?? RecentCasesStore()
        self.status = initialCase?.status ?? .collectingInformation
        self.currentQuestion = initialCase?.nextQuestion
        self.isLoadingCase = initialCase == nil
        self.medicalDictionary = medicalDictionary
        self.phiFilter = phiFilter ?? .shared
        self.dictation = dictation ?? DictationController(medicalDictionary: medicalDictionary)
        self.dictation.onCorrectedText = { [weak self] text in
            self?.answerText = text
        }
        observeDictation()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    var canSubmitAnswer: Bool {
        dictationPhase == .idle && !isSubmittingAnswer
            && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleDictation() async {
        await dictation.toggleDictation(currentText: answerText)
    }

    func loadIfNeeded() async {
        guard isLoadingCase else { return }
        do {
            let result = try await BackendService.getCase(caseId: caseId)
            apply(result)
        } catch {
            errorMessage = Self.message(for: error)
        }
        isLoadingCase = false
    }

    func submitAnswer() async {
        guard let question = currentQuestion else { return }
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter an answer before submitting."
            return
        }

        // Final on-device PHI screen before anything is sent to the
        // backend (which forwards the answer to OpenAI) -- catches PHI
        // typed by hand, which dictation-time screening never saw.
        let phiResult = phiFilter.redact(trimmed)
        if phiResult.hasFindings {
            answerText = phiResult.redactedText
            phiNoticeMessage = phiResult.noticeMessage
            return
        }

        errorMessage = nil
        isSubmittingAnswer = true
        defer { isSubmittingAnswer = false }

        do {
            let result = try await BackendService.answerQuestion(caseId: caseId,
                                                                   questionId: question.id,
                                                                   answer: trimmed)
            apply(result)
            answerText = ""
        } catch {
            // Preserve answerText so the trainee doesn't lose what they typed.
            errorMessage = Self.message(for: error)
        }
    }

    /// Finalizes the case and returns the completed case, or nil on failure.
    func finalize() async -> MMCase? {
        errorMessage = nil
        isFinalizing = true
        defer { isFinalizing = false }

        do {
            let result = try await BackendService.finalizeCase(caseId: caseId)
            apply(result)
            return result
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private func apply(_ result: MMCase) {
        status = result.status
        currentQuestion = result.nextQuestion
        store.updateStatus(id: caseId, status: result.status)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
    }

    private func observeDictation() {
        let phaseTask = Task { [weak self] in
            guard let self else { return }
            for await phase in self.dictation.$dictationPhase.values {
                self.dictationPhase = phase
            }
        }
        let errorTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.dictation.$dictationErrorMessage.values {
                self.dictationErrorMessage = message
            }
        }
        let phiTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.dictation.$phiNoticeMessage.values {
                guard message != nil else { continue }
                self.phiNoticeMessage = message
            }
        }
        observationTasks = [phaseTask, errorTask, phiTask]
    }
}
