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
    @Published private(set) var isLoading: Bool
    @Published var errorMessage: String?

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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
        }
        isLoading = false
    }
}
