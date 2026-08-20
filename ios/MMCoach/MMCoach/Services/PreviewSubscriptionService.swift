//
//  PreviewSubscriptionService.swift
//  MMCoach
//
//  Mock `SubscriptionService` implementation, kept in Services/ alongside
//  the protocol it implements -- mirrors PreviewAuthenticationService. Used
//  by SwiftUI previews (see PaywallView, HomeView) and available the same
//  way to a future unit test target: the protocol boundary this mocks is
//  exactly what makes PaywallViewModel/HomeViewModel testable without
//  StoreKit.
//

#if DEBUG
import Foundation

struct PreviewSubscriptionService: SubscriptionService {
    var plansResult: Result<[SubscriptionPlan], Error> = .success(.previewPlans)
    var purchaseResult: Result<SubscriptionPurchaseOutcome, Error> = .success(.success)
    var restoreError: Error?
    var hasActiveEntitlementResult = false

    /// Simulated delay before resolving, so previews/manual testing can
    /// show the loading/purchasing/restoring states rather than flashing
    /// straight past them.
    var delay: Duration = .seconds(0)

    func loadPlans() async throws -> [SubscriptionPlan] {
        try await Task.sleep(for: delay)
        return try plansResult.get()
    }

    func purchase(productID: String) async throws -> SubscriptionPurchaseOutcome {
        try await Task.sleep(for: delay)
        return try purchaseResult.get()
    }

    func restorePurchases() async throws {
        try await Task.sleep(for: delay)
        if let restoreError { throw restoreError }
    }

    func hasActiveEntitlement() async -> Bool {
        hasActiveEntitlementResult
    }
}

extension Array where Element == SubscriptionPlan {
    static let previewPlans: [SubscriptionPlan] = [
        SubscriptionPlan(id: SubscriptionProductID.annual,
                          period: .annual,
                          displayName: "M & M Coach Annual",
                          displayPrice: "$10.99"),
        SubscriptionPlan(id: SubscriptionProductID.monthly,
                          period: .monthly,
                          displayName: "M & M Coach Monthly",
                          displayPrice: "$1.99"),
    ]
}
#endif
