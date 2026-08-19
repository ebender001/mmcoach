//
//  HomeViewModel.swift
//  MMCoach
//

import Foundation
import Combine
import SwiftUI

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

    /// Removes cases at the given offsets from the local index (e.g. via
    /// swipe-to-delete/EditButton). Only forgets them locally -- the
    /// underlying case still exists on the backend.
    func deleteRecentCases(at offsets: IndexSet) {
        for index in offsets {
            store.remove(id: recentCases[index].id)
        }
        recentCases.remove(atOffsets: offsets)
    }
}
