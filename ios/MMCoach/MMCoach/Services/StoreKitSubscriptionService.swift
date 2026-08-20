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
        let products: [Product]
        do {
            products = try await Product.products(for: SubscriptionProductID.all)
        } catch {
            throw SubscriptionServiceError.network
        }
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
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
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
        do {
            try await AppStore.sync()
            // Discard the cache rather than assume anything -- restore can
            // reveal an entitlement this process never observed itself
            // (or reveal that one is now gone), so the next
            // hasActiveEntitlement() call should do a real scan.
            knownActiveEntitlement = nil
        } catch {
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

    private static func plan(for product: Product) -> SubscriptionPlan {
        let period: SubscriptionPeriod = product.id == SubscriptionProductID.annual ? .annual : .monthly
        return SubscriptionPlan(id: product.id,
                                 period: period,
                                 displayName: product.displayName,
                                 displayPrice: product.displayPrice)
    }
}
