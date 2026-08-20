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
    /// Set alongside `isPresentingPaywall = false` when the paywall closed
    /// because access was unlocked (vs. the person swiping it away).
    /// Consumed by `consumePaywallUnlock()` from the sheet's `onDismiss`,
    /// once the dismissal has actually finished -- see HomeView.
    private var didUnlockCaseAccessViaPaywall = false

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
    /// (purchase, restore, or the free case). Only flips the binding that
    /// closes the sheet -- deliberately does NOT push `.newCase` itself.
    /// Pushing here would race the sheet's own dismiss animation (both
    /// mutating navigation state in the same tick); the push instead
    /// happens from the sheet's `onDismiss`, once SwiftUI confirms the
    /// dismissal actually completed (see HomeView, `consumePaywallUnlock()`).
    func paywallDidUnlockAccess() {
        didUnlockCaseAccessViaPaywall = true
        isPresentingPaywall = false
    }

    /// Call from the paywall sheet's `onDismiss`. Returns whether the sheet
    /// closed because access was unlocked (vs. a manual swipe-to-dismiss),
    /// consuming the flag either way so it can't fire twice.
    func consumePaywallUnlock() -> Bool {
        defer { didUnlockCaseAccessViaPaywall = false }
        return didUnlockCaseAccessViaPaywall
    }
}
