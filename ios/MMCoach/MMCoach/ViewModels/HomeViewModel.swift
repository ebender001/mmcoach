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
    /// Bound directly to the paywall sheet's `isPresented` (see HomeView) --
    /// not `private(set)`, since dismissing the sheet (swipe-down) must be
    /// able to set this back to `false` too.
    @Published var isPresentingPaywall = false
    @Published private(set) var isCheckingCaseAccess = false

    private let store: RecentCasesStore
    private let subscriptionService: SubscriptionService

    init(store: RecentCasesStore? = nil, subscriptionService: SubscriptionService? = nil) {
        self.store = store ?? RecentCasesStore()
        self.subscriptionService = subscriptionService ?? StoreKitSubscriptionService.shared
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

    /// The case-access gate behind "Start a New Case": an active
    /// subscriber proceeds directly, everyone else sees the paywall.
    /// Entitlement is re-checked fresh against StoreKit every call, never
    /// cached. Guarded against re-entrancy (`isCheckingCaseAccess`, and
    /// bailing if the paywall is already up) so repeatedly tapping the
    /// button never kicks off overlapping checks or presents the sheet
    /// twice. Returns whether the caller should push `.newCase` now.
    func startNewCase() async -> Bool {
        guard !isCheckingCaseAccess, !isPresentingPaywall else { return false }
        isCheckingCaseAccess = true
        defer { isCheckingCaseAccess = false }

        if await subscriptionService.hasActiveEntitlement() {
            return true
        }
        isPresentingPaywall = true
        return false
    }

    /// Called once PaywallView confirms the person unlocked access
    /// (purchase, restore, or the free case) -- dismisses the sheet so the
    /// caller can push `.newCase`.
    func paywallDidUnlockAccess() {
        isPresentingPaywall = false
    }
}
