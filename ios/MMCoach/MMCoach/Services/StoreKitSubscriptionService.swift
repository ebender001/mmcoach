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
        } catch {
            throw SubscriptionServiceError.network
        }
    }

    func hasActiveEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            if SubscriptionProductID.all.contains(transaction.productID), transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    private func finish(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? Self.checkVerified(update) else { return }
        await transaction.finish()
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
