//
//  ReferenceLookupViewModel.swift
//  MMCoach
//
//  Drives ReferenceLookupView: an on-demand PubMed search for one
//  reference topic, triggered by tapping a card in ReferencesView.
//

import Combine
import Foundation

@MainActor
final class ReferenceLookupViewModel: ObservableObject {
    let topic: String
    let searchIntent: String
    private let caseId: String?

    @Published private(set) var results: [PubMedReference] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasSearched = false

    /// - Parameter caseId: Passed through to the backend when known so it
    ///   can verify ownership and roll this search's AI cost into that
    ///   case's running total. `nil` is still handled gracefully server-side
    ///   (just skips both), it just shouldn't happen from any real screen.
    init(topic: String, searchIntent: String, caseId: String?) {
        self.topic = topic
        self.searchIntent = searchIntent
        self.caseId = caseId
    }

    func search() async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
        }

        do {
            results = try await BackendService.findReferences(topic: topic, searchIntent: searchIntent, caseId: caseId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
        }
    }
}
