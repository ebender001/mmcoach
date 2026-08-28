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
    /// True only when `cachedResults` was supplied at init -- distinct
    /// from `hasSearched` (which also becomes true after a live search,
    /// including a failed one) so a retry after a genuine search failure
    /// still runs, while a cache hit is never re-fetched.
    private let isPrefetchedFromCache: Bool

    /// - Parameter caseId: Passed through to the backend when known so it
    ///   can verify ownership and roll this search's AI cost into that
    ///   case's running total. `nil` is still handled gracefully server-side
    ///   (just skips both), it just shouldn't happen from any real screen.
    /// - Parameter cachedResults: Results the backend already found and
    ///   returned inline on the case (`MMCase.referenceLookups`). When
    ///   present, `search()` never calls the backend at all -- this is
    ///   exactly what `mmFindReferences` would return for this topic.
    init(topic: String, searchIntent: String, caseId: String?, cachedResults: [PubMedReference]? = nil) {
        self.topic = topic
        self.searchIntent = searchIntent
        self.caseId = caseId
        if let cachedResults {
            self.results = cachedResults
            self.hasSearched = true
            self.isPrefetchedFromCache = true
        } else {
            self.isPrefetchedFromCache = false
        }
    }

    func search() async {
        guard !isLoading, !isPrefetchedFromCache else { return }
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
