//
//  StoreKitSubscriptionService.swift
//  MMCoach
//
//  The only concrete SubscriptionService. StoreKit 2 and Apple in-app
//  purchases only -- no third-party payment SDK. `.shared` is a genuine
//  app-wide singleton (like SpecialtyStore.shared) rather than something
//  created per-view: it owns the one long-lived Transaction.updates
//  listener for the app's lifetime, so creating more than one instance
//  would mean redundant listeners.
//

import Foundation
import StoreKit

/// Internal signal that `withStoreKitTimeout` gave up waiting -- always
/// translated to `SubscriptionServiceError.timedOut` before leaving this
/// file, never surfaced to callers directly.
private struct StoreKitTimeoutError: Error {}

@MainActor
final class StoreKitSubscriptionService: SubscriptionService {
    static let shared = StoreKitSubscriptionService()

    private var productsByID: [String: Product] = [:]
    private var transactionListener: Task<Void, Never>?
    /// Fast-path entitlement cache, populated *only* from verified StoreKit
    /// signals this process has actually observed -- a purchase this
    /// service itself completed, or an update from the `Transaction.updates`
    /// listener (which also fires on renewals and revocations). This is
    /// not a durable/persisted flag: it resets on relaunch, forcing a fresh
    /// `Transaction.currentEntitlements` scan. It exists because that scan
    /// can briefly lag behind a transaction finished moments earlier in
    /// this same process -- without this, `hasActiveEntitlement()` called
    /// immediately after a successful purchase (as PaywallViewModel does,
    /// to decide whether to dismiss) can see stale state. `nil` means "not
    /// yet known."
    private var knownActiveEntitlement: Bool?

    /// How long to wait on `product.purchase()` / `AppStore.sync()` before
    /// giving up. Apple's own StoreKit sheet has occasionally been observed
    /// (including during App Review) to hang at its own "Loading" state
    /// indefinitely -- see Guideline 2.1(b) rejection: "the purchase loads
    /// indefinitely and does not successfully complete." Without a timeout
    /// here, `purchase(productID:)`/`restorePurchases()` never return and
    /// the paywall has nothing to recover from. A transaction that
    /// eventually *does* complete after we've given up is still picked up
    /// by the `Transaction.updates` listener above.
    private static let storeKitTimeout: Duration = .seconds(30)

    private init() {
        // Catches transactions that complete outside purchase()'s own
        // await -- Ask to Buy approvals, renewals, and any transaction
        // StoreKit delivers asynchronously -- so they're always finished
        // rather than left pending indefinitely.
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.finish(update)
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadPlans() async throws -> [SubscriptionPlan] {
        #if DEBUG
        print("[StoreKit] Product.products(for:) requesting \(SubscriptionProductID.all)")
        #endif
        let products: [Product]
        do {
            products = try await Product.products(for: SubscriptionProductID.all)
        } catch {
            #if DEBUG
            print("[StoreKit] Product.products(for:) threw: \(error)")
            #endif
            throw SubscriptionServiceError.network
        }
        #if DEBUG
        print("[StoreKit] Product.products(for:) returned \(products.count) product(s): \(products.map(\.id))")
        #endif
        guard !products.isEmpty else {
            throw SubscriptionServiceError.productsUnavailable
        }
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return products.map(Self.plan(for:))
    }

    func purchase(productID: String) async throws -> SubscriptionPurchaseOutcome {
        guard let product = productsByID[productID] else {
            throw SubscriptionServiceError.productsUnavailable
        }
        #if DEBUG
        print("[StoreKit] Starting purchase for \(productID)")
        #endif
        let result: Product.PurchaseResult
        do {
            result = try await Self.withStoreKitTimeout { try await product.purchase() }
        } catch is StoreKitTimeoutError {
            #if DEBUG
            print("[StoreKit] Purchase for \(productID) timed out after \(Self.storeKitTimeout)")
            #endif
            throw SubscriptionServiceError.timedOut
        } catch {
            #if DEBUG
            print("[StoreKit] product.purchase() threw: \(error)")
            #endif
            throw SubscriptionServiceError.unknown
        }

        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            recordKnownEntitlement(from: transaction)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws {
        #if DEBUG
        print("[StoreKit] Starting restore (AppStore.sync())")
        #endif
        do {
            try await Self.withStoreKitTimeout { try await AppStore.sync() }
            // Discard the cache rather than assume anything -- restore can
            // reveal an entitlement this process never observed itself
            // (or reveal that one is now gone), so the next
            // hasActiveEntitlement() call should do a real scan.
            knownActiveEntitlement = nil
        } catch is StoreKitTimeoutError {
            #if DEBUG
            print("[StoreKit] Restore timed out after \(Self.storeKitTimeout)")
            #endif
            throw SubscriptionServiceError.timedOut
        } catch {
            #if DEBUG
            print("[StoreKit] AppStore.sync() threw: \(error)")
            #endif
            throw SubscriptionServiceError.network
        }
    }

    func hasActiveEntitlement() async -> Bool {
        if let knownActiveEntitlement {
            return knownActiveEntitlement
        }
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            if SubscriptionProductID.all.contains(transaction.productID), transaction.revocationDate == nil {
                knownActiveEntitlement = true
                return true
            }
        }
        knownActiveEntitlement = false
        return false
    }

    private func finish(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? Self.checkVerified(update) else { return }
        recordKnownEntitlement(from: transaction)
        await transaction.finish()
    }

    /// Updates the fast-path cache from a transaction StoreKit has already
    /// verified for us -- a purchase this service just completed, or a
    /// `Transaction.updates` delivery (renewal, revocation, refund).
    /// Ignores transactions for products this app doesn't sell.
    private func recordKnownEntitlement(from transaction: Transaction) {
        guard SubscriptionProductID.all.contains(transaction.productID) else { return }
        knownActiveEntitlement = transaction.revocationDate == nil
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionServiceError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    /// Races `operation` against `storeKitTimeout`, whichever finishes
    /// first. `operation`'s own `Task` is cancelled if the timeout wins --
    /// StoreKit isn't guaranteed to honor that cancellation immediately,
    /// which is fine: this only needs to stop *this call* from blocking
    /// the paywall forever, and the `Transaction.updates` listener still
    /// picks up a transaction that completes later regardless.
    private static func withStoreKitTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: storeKitTimeout)
                throw StoreKitTimeoutError()
            }
            defer { group.cancelAll() }
            let result = try await group.next()!
            return result
        }
    }

    private static func plan(for product: Product) -> SubscriptionPlan {
        let period: SubscriptionPeriod = product.id == SubscriptionProductID.annual ? .annual : .monthly
        return SubscriptionPlan(id: product.id,
                                 period: period,
                                 displayName: product.displayName,
                                 displayPrice: product.displayPrice)
    }
}
