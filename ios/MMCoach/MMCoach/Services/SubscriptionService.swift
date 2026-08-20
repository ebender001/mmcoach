//
//  SubscriptionService.swift
//  MMCoach
//
//  The single interface between MMCoach and Apple in-app purchases. Views
//  and view models never call StoreKit directly -- see PaywallViewModel and
//  HomeViewModel, the only callers of this protocol, and
//  StoreKitSubscriptionService, the only concrete implementation.
//  Protocol-based so it can be mocked in previews/tests (see
//  PreviewSubscriptionService), mirroring AuthenticationService.
//
//  Flow: View -> ViewModel -> SubscriptionService -> StoreKit.
//

import Foundation

/// The app's two configured auto-renewing subscription products. These
/// must match the App Store Connect product identifiers exactly, and the
/// identifiers configured in the local StoreKit configuration file used
/// for development testing (see Paywall/MMCoach.storekit).
enum SubscriptionProductID {
    static let monthly = "dev.benderapps.MMCoach.subscription.monthly"
    static let annual = "dev.benderapps.MMCoach.subscription.annual"
    static let all = [annual, monthly]
}

enum SubscriptionPeriod: Equatable {
    case monthly
    case annual
}

/// Display-facing view of a StoreKit `Product`. Kept separate from the
/// StoreKit type itself so views and view models never need to import
/// StoreKit directly.
struct SubscriptionPlan: Identifiable, Equatable {
    let id: String
    let period: SubscriptionPeriod
    /// Localized product name, as configured in App Store Connect (or the
    /// local StoreKit configuration file).
    let displayName: String
    /// Localized, formatted total price for the period (e.g. "$10.99") --
    /// always the real StoreKit price, never a hard-coded string. For the
    /// annual plan this is the annual total, not a monthly equivalent.
    let displayPrice: String
}

enum SubscriptionPurchaseOutcome: Equatable {
    case success
    /// The person dismissed the purchase sheet -- not an error.
    case userCancelled
    /// Awaiting approval (e.g. Ask to Buy) -- not an error; there is
    /// nothing more to do until the approval resolves.
    case pending
}

/// User-facing errors surfaced by `SubscriptionService`. Raw StoreKit error
/// text is never shown to the trainee -- only these concise messages.
enum SubscriptionServiceError: LocalizedError, Equatable {
    case productsUnavailable
    case verificationFailed
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            return "Subscription plans aren't available right now. Please try again."
        case .verificationFailed:
            return "We couldn't verify that purchase. Please try again or contact support."
        case .network:
            return "M & M Coach couldn't reach the App Store. Check your connection and try again."
        case .unknown:
            return "Something went wrong with that purchase. Please try again."
        }
    }
}

protocol SubscriptionService {
    /// Loads the configured subscription products from StoreKit. Order is
    /// not guaranteed -- callers sort as needed.
    func loadPlans() async throws -> [SubscriptionPlan]

    /// Starts a purchase for the given product id (must be one returned by
    /// `loadPlans()`).
    func purchase(productID: String) async throws -> SubscriptionPurchaseOutcome

    /// Re-syncs entitlements from the App Store. Only ever called from an
    /// explicit "Restore Purchases" action -- never automatically.
    func restorePurchases() async throws

    /// Whether the signed-in Apple ID currently holds a verified, active
    /// entitlement for either subscription product. Always checked fresh
    /// against StoreKit's current entitlements -- never a cached/local flag.
    func hasActiveEntitlement() async -> Bool
}
