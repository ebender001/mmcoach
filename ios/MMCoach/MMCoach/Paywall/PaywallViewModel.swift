//
//  PaywallViewModel.swift
//  MMCoach
//
//  Drives PaywallView. Loads the configured subscription plans and the
//  signed-in user's backend case count in parallel, and owns the
//  purchase/restore/free-case state machine. Views never call
//  SubscriptionService or BackendService directly -- only this.
//

import Combine
import Foundation

enum PaywallState: Equatable {
    case loadingProducts
    case ready
    case purchasing(productID: String)
    case restoring
    /// Redeeming "Continue with Your Free Case" -- a real network call
    /// (see BackendService.redeemFreeCase), not an instant local flag
    /// flip, so it needs its own busy state like purchasing/restoring do.
    case redeemingFreeCase
    /// Also covers a `loadPlans()` failure (see `load()`) -- from the
    /// trainee's point of view, "plans didn't load" and "a purchase
    /// failed" both mean "nothing was purchased, here's why, try again."
    case purchaseFailed(message: String)
    case restoreFailed(message: String)
}

/// Whether the signed-in user qualifies for "Continue with Your Free
/// Case" -- backend-sourced, never assumed. `.unknown` is intentionally
/// *not* a case here: a failed case-count fetch fails closed to
/// `.notEligible` (see `loadFreeCaseEligibility()`) rather than blocking
/// the rest of the paywall on a retry.
enum FreeCaseEligibility: Equatable {
    case checking
    case eligible
    case notEligible
}

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published private(set) var state: PaywallState = .loadingProducts
    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var freeCaseEligibility: FreeCaseEligibility = .checking
    /// Flips to `true` once a purchase, a restore, or the free-case action
    /// has confirmed the person should proceed. `PaywallView` observes this
    /// to dismiss itself and continue to the new-case workflow.
    @Published private(set) var didUnlockAccess = false

    var sortedPlans: [SubscriptionPlan] {
        // Annual first (visually recommended) regardless of the order
        // StoreKit/the mock returns them in.
        plans.sorted { lhs, _ in lhs.period == .annual }
    }

    var isBusy: Bool {
        switch state {
        case .purchasing, .restoring, .redeemingFreeCase:
            return true
        case .loadingProducts, .ready, .purchaseFailed, .restoreFailed:
            return false
        }
    }

    private let subscriptionService: SubscriptionService
    private let fetchFreeCaseEligibility: () async throws -> Bool
    private let redeemFreeCase: () async throws -> Void

    init(subscriptionService: SubscriptionService? = nil,
         fetchFreeCaseEligibility: @escaping () async throws -> Bool = {
             try await BackendService.checkFreeCaseEligibility(deviceId: DeviceIdentifierService.current())
         },
         redeemFreeCase: @escaping () async throws -> Void = {
             try await BackendService.redeemFreeCase(deviceId: DeviceIdentifierService.current())
         }) {
        self.subscriptionService = subscriptionService ?? StoreKitSubscriptionService.shared
        self.fetchFreeCaseEligibility = fetchFreeCaseEligibility
        self.redeemFreeCase = redeemFreeCase
    }

    /// Loads plans and the free-case eligibility check together. Call once
    /// from the sheet's `.task`.
    func load() async {
        state = .loadingProducts
        freeCaseEligibility = .checking
        async let plansResult: Void = loadPlans()
        async let eligibilityResult: Void = loadFreeCaseEligibility()
        _ = await (plansResult, eligibilityResult)
    }

    func purchase(_ plan: SubscriptionPlan) async {
        guard !isBusy else { return }
        state = .purchasing(productID: plan.id)
        do {
            let outcome = try await subscriptionService.purchase(productID: plan.id)
            switch outcome {
            case .success:
                await refreshEntitlementAndUnlock()
            case .userCancelled:
                // Not an error -- leave the trainee on the paywall.
                state = .ready
            case .pending:
                // Awaiting approval (e.g. Ask to Buy); nothing more to do
                // here -- the transaction listener finishes it if/when it
                // resolves.
                state = .ready
            }
        } catch {
            state = .purchaseFailed(message: Self.message(for: error))
        }
    }

    func restore() async {
        guard !isBusy else { return }
        state = .restoring
        do {
            try await subscriptionService.restorePurchases()
            if await subscriptionService.hasActiveEntitlement() {
                didUnlockAccess = true
                state = .ready
            } else {
                state = .restoreFailed(message: "No active subscription was found to restore.")
            }
        } catch {
            state = .restoreFailed(message: Self.message(for: error))
        }
    }

    /// Only valid when `freeCaseEligibility == .eligible` -- the view only
    /// shows this action in that state, but guard here too since this is
    /// the actual access decision. Calls the backend to atomically
    /// re-validate and record the redemption (see
    /// BackendService.redeemFreeCase) rather than trusting the earlier
    /// eligibility check alone -- that check only decided whether to
    /// *show* this button, not whether it's still safe to grant.
    func continueWithFreeCase() async {
        guard freeCaseEligibility == .eligible, !isBusy else { return }
        state = .redeemingFreeCase
        do {
            try await redeemFreeCase()
            didUnlockAccess = true
            state = .ready
        } catch {
            state = .purchaseFailed(message: Self.message(for: error))
            // The backend just said this account/device is no longer
            // eligible (or the check itself failed) -- refresh so a
            // stale "Continue with Your Free Case" button doesn't linger.
            await loadFreeCaseEligibility()
        }
    }

    private func loadPlans() async {
        do {
            plans = try await subscriptionService.loadPlans()
            state = .ready
        } catch {
            state = .purchaseFailed(message: Self.message(for: error))
        }
    }

    private func loadFreeCaseEligibility() async {
        do {
            let eligible = try await fetchFreeCaseEligibility()
            freeCaseEligibility = eligible ? .eligible : .notEligible
        } catch {
            // Fail closed: if the backend can't confirm eligibility,
            // don't offer the free-case path. Subscribing/restoring are
            // unaffected by this failure.
            freeCaseEligibility = .notEligible
        }
    }

    private func refreshEntitlementAndUnlock() async {
        if await subscriptionService.hasActiveEntitlement() {
            didUnlockAccess = true
        }
        state = .ready
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? SubscriptionServiceError.unknown.errorDescription!
    }
}
