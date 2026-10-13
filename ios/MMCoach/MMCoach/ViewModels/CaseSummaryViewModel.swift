//
//  CaseSummaryViewModel.swift
//  MMCoach
//

import Foundation
import Combine

@MainActor
final class CaseSummaryViewModel: ObservableObject {
    let caseId: String

    @Published private(set) var polishedNarrative: String
    @Published private(set) var discussionPreparation: [DiscussionTopic]
    @Published private(set) var likelyFacultyQuestions: [String]
    @Published private(set) var references: [ReferenceItem]
    /// Faculty questions already answered on this case, keyed by question
    /// text -- passed down to FacultyQuestionsView so a cached answer
    /// skips `mmAnswerFacultyQuestion` entirely (see
    /// FacultyQuestionAnswerViewModel).
    @Published private(set) var facultyQuestionAnswers: [String: String]
    /// Reference topics already looked up on this case, keyed by topic --
    /// passed down to ReferencesView so a cached lookup skips
    /// `mmFindReferences` entirely (see ReferenceLookupViewModel).
    @Published private(set) var referenceLookups: [String: CachedReferenceLookup]
    @Published private(set) var isLoading: Bool
    @Published var errorMessage: String?
    @Published private(set) var isSavingNarrative = false

    /// - Parameter initialCase: Pass the case snapshot already returned by
    ///   mmFinalizeCase when navigating here right after finalizing, so no
    ///   extra network round trip is needed. Pass `nil` when opening an
    ///   already-completed case from Home.
    init(caseId: String, initialCase: MMCase?) {
        self.caseId = caseId
        self.polishedNarrative = initialCase?.polishedNarrative ?? ""
        self.discussionPreparation = initialCase?.discussionPreparation ?? []
        self.likelyFacultyQuestions = initialCase?.likelyFacultyQuestions ?? []
        self.references = initialCase?.references ?? []
        self.facultyQuestionAnswers = initialCase?.facultyQuestionAnswers ?? [:]
        self.referenceLookups = initialCase?.referenceLookups ?? [:]
        self.isLoading = initialCase == nil
    }

    func loadIfNeeded() async {
        guard isLoading else { return }
        do {
            let result = try await BackendService.getCase(caseId: caseId)
            polishedNarrative = result.polishedNarrative ?? polishedNarrative
            discussionPreparation = result.discussionPreparation
            likelyFacultyQuestions = result.likelyFacultyQuestions
            references = result.references
            facultyQuestionAnswers = result.facultyQuestionAnswers
            referenceLookups = result.referenceLookups
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
        }
        isLoading = false
    }

    /// Persists a hand-edited polished narrative. Returns whether it
    /// succeeded; on success `polishedNarrative` already reflects the
    /// edit, on failure `errorMessage` is set and the caller should keep
    /// its editing UI open so the trainee doesn't lose the edit.
    @discardableResult
    func updatePolishedNarrative(_ text: String) async -> Bool {
        guard !isSavingNarrative else { return false }
        errorMessage = nil
        isSavingNarrative = true
        defer { isSavingNarrative = false }

        do {
            let result = try await BackendService.updatePolishedNarrative(caseId: caseId, polishedNarrative: text)
            polishedNarrative = result.polishedNarrative ?? text
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
            return false
        }
    }
}
