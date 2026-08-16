//
//  HomeViewModel.swift
//  MMCoach
//

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var recentCases: [RecentCaseRecord] = []

    private let store: RecentCasesStore

    init(store: RecentCasesStore? = nil) {
        self.store = store ?? RecentCasesStore()
    }

    /// Reloads the local case index. Call from `.onAppear`/`.task` so the
    /// list reflects cases created or progressed on other screens.
    func refresh() {
        recentCases = store.loadAll()
    }
}
