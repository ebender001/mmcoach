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
    @Published var answerText = ""
    @Published private(set) var isLoadingCase: Bool
    @Published private(set) var isSubmittingAnswer = false
    @Published private(set) var isFinalizing = false
    @Published var errorMessage: String?

    private let store: RecentCasesStore

    /// - Parameter initialCase: Pass the case snapshot already returned by
    ///   mmCreateCase/mmAnswerQuestion when navigating here right after
    ///   that call, so no extra network round trip is needed. Pass `nil`
    ///   when resuming an in-progress case from Home; the view model will
    ///   fetch current state via `loadIfNeeded()`.
    init(caseId: String, initialCase: MMCase?, store: RecentCasesStore? = nil) {
        self.caseId = caseId
        self.store = store ?? RecentCasesStore()
        self.status = initialCase?.status ?? .collectingInformation
        self.currentQuestion = initialCase?.nextQuestion
        self.isLoadingCase = initialCase == nil
    }

    var canSubmitAnswer: Bool {
        !isSubmittingAnswer && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
}
