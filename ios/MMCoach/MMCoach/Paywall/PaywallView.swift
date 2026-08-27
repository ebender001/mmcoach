//
//  PaywallView.swift
//  MMCoach
//
//  The subscription paywall, presented as a large-detent sheet when a
//  non-subscribed trainee taps "Start a New Case" (see HomeViewModel).
//  Content order: header, benefits, subscription plans, first-free-case
//  (only for a zero-case account), restore purchases, legal footer.
//

import SwiftUI

struct PaywallView: View {
    @StateObject private var viewModel: PaywallViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called exactly once, when a purchase, a restore, or the free-case
    /// action confirms the person should proceed to the new-case workflow.
    /// The caller owns dismissing the sheet and pushing the new-case
    /// route -- this view doesn't call `dismiss()` itself, since doing so
    /// alongside the caller's own dismissal would race it (see HomeView).
    let onUnlocked: () -> Void

    init(viewModel: PaywallViewModel? = nil, onUnlocked: @escaping () -> Void) {
        // Built inside the initializer body, not as the parameter's default
        // value -- a default-argument expression runs outside this type's
        // actor context, but `PaywallViewModel.init` is @MainActor-isolated.
        _viewModel = StateObject(wrappedValue: viewModel ?? PaywallViewModel())
        self.onUnlocked = onUnlocked
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    benefits
                    plansSection
                    if viewModel.freeCaseEligibility == .eligible {
                        freeCaseSection
                    }
                    restoreSection
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color.warmBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.slateText)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Avoid dismissing mid-transaction -- the system's own StoreKit
        // sheet is already layered above this one during a purchase.
        .interactiveDismissDisabled(viewModel.isBusy)
        .task { await viewModel.load() }
        .onChange(of: viewModel.didUnlockAccess) { _, unlocked in
            // Only notify the caller here -- don't call `dismiss()`
            // ourselves. The caller flips the `isPresented` binding it
            // owns (see HomeViewModel.paywallDidUnlockAccess()), which
            // dismisses this sheet from the outside; calling `dismiss()`
            // here too would race that same dismissal from both sides.
            guard unlocked else { return }
            onUnlocked()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.mutedTeal.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundStyle(Color.mutedTeal)
            }
            .accessibilityHidden(true)

            Text("Prepare every case with confidence")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text("Build a clear M&M presentation with guided clinical questions, discussion preparation, and relevant PubMed abstracts.")
                .font(.subheadline)
                .foregroundStyle(Color.slateText)
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallBenefitRow(icon: "list.bullet.clipboard",
                               title: "Guided case development",
                               detail: "Clarify the clinical timeline and key decision points.")
            PaywallBenefitRow(icon: "text.book.closed",
                               title: "Conference preparation",
                               detail: "Review a polished narrative, discussion topics, and likely questions.")
            PaywallBenefitRow(icon: "magnifyingglass",
                               title: "Relevant literature",
                               detail: "Automatically search PubMed for abstracts relevant to the case.")
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plansSection: some View {
        switch viewModel.state {
        case .loadingProducts:
            HStack {
                Spacer()
                ProgressView("Loading plans…")
                Spacer()
            }
            .padding(.vertical, 32)

        case .unableToLoadProducts:
            // The initial product request (plus its automatic retries --
            // see PaywallViewModel.attemptLoadPlans()) never came back with
            // any products. Never leave a reviewer/trainee stuck on the
            // spinner above -- show a clean, non-technical error with a
            // way to retry instead.
            VStack(spacing: 12) {
                Text("Unable to Load Subscriptions")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text("Subscription options couldn't be loaded from the App Store. Please check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateText)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.michiganBordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

        default:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.sortedPlans) { plan in
                    SubscriptionPlanCard(
                        plan: plan,
                        isRecommended: plan.period == .annual,
                        isBusy: viewModel.isBusy,
                        isPurchasingThis: viewModel.state == .purchasing(productID: plan.id)
                    ) {
                        Task { await viewModel.purchase(plan) }
                    }
                }

                if case .purchaseFailed(let message) = viewModel.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("Subscriptions automatically renew unless canceled.")
                    .font(.caption)
                    .foregroundStyle(Color.slateText)
            }
        }
    }

    // MARK: - First free case

    private var freeCaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.5)

            Text("Your first complete case preparation is free.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Button {
                Task { await viewModel.continueWithFreeCase() }
            } label: {
                HStack {
                    if viewModel.state == .redeemingFreeCase {
                        ProgressView()
                    } else {
                        Text("Continue with Your Free Case")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.michiganBordered)
            .disabled(viewModel.isBusy)
        }
    }

    // MARK: - Restore

    private var restoreSection: some View {
        VStack(spacing: 6) {
            if case .restoreFailed(let message) = viewModel.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 4) {
                Text("Already subscribed?")
                    .foregroundStyle(Color.slateText)
                Button {
                    Task { await viewModel.restore() }
                } label: {
                    if viewModel.state == .restoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                            .underline()
                            .foregroundStyle(Color.michiganBlueText)
                    }
                }
                .disabled(viewModel.isBusy)
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. Manage or cancel in Apple Account Settings.")
                .font(.caption2)
                .foregroundStyle(Color.slateText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                Text("·").foregroundStyle(Color.slateText)
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
            }
            .font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview("Ready, zero cases") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(),
                    fetchFreeCaseEligibility: { true },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Ready, existing cases (no free-case section)") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(),
                    fetchFreeCaseEligibility: { false },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Purchasing") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(delay: .seconds(120)),
                    fetchFreeCaseEligibility: { true },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Product load failure (all retries fail)") {
    // Every attempt fails, so this shows the spinner for ~3s (2 automatic
    // retries, ~1.5s apart) before landing on the unable-to-load state.
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(plansResult: .failure(SubscriptionServiceError.productsUnavailable)),
                    fetchFreeCaseEligibility: { true },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Backend eligibility check failure (fails closed)") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(),
                    fetchFreeCaseEligibility: { throw BackendError.network },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Redeeming free case fails") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(),
                    fetchFreeCaseEligibility: { true },
                    redeemFreeCase: { throw BackendError.invalidState("A free case is not available for this account.") }
                ),
                onUnlocked: {}
            )
        }
}

#Preview("Dynamic Type - XXL") {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            PaywallView(
                viewModel: PaywallViewModel(
                    subscriptionService: PreviewSubscriptionService(),
                    fetchFreeCaseEligibility: { true },
                    redeemFreeCase: {}
                ),
                onUnlocked: {}
            )
        }
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
#endif
