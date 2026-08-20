//
//  SubscriptionPlanCard.swift
//  MMCoach
//
//  One subscription plan on PaywallView. The whole card is the purchase
//  action -- tapping it buys that plan directly, consistent with the
//  card-as-button language already used by NewCaseActionCard.
//

import SwiftUI

struct SubscriptionPlanCard: View {
    let plan: SubscriptionPlan
    let isRecommended: Bool
    /// Whether *any* plan purchase/restore is currently in flight -- used
    /// to disable every card (not just this one) while one is purchasing.
    let isBusy: Bool
    /// Whether this specific card's purchase is the one in flight.
    let isPurchasingThis: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isRecommended {
                            StatusBadge(text: "Best Value", tint: Color.mutedTeal)
                        }
                    }
                    Text(priceLine)
                        .font(.subheadline)
                        .foregroundStyle(Color.slateText)
                }

                Spacer(minLength: 0)

                if isPurchasingThis {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.slateText)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isRecommended ? Color.mutedTeal.opacity(0.55) : Color.primary.opacity(0.08),
                                  lineWidth: isRecommended ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy && !isPurchasingThis ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var priceLine: String {
        switch plan.period {
        case .annual: "\(plan.displayPrice)/year"
        case .monthly: "\(plan.displayPrice)/month"
        }
    }

    private var accessibilityLabel: String {
        var label = "\(plan.displayName), \(priceLine)"
        if isRecommended { label += ", best value" }
        if isPurchasingThis { label += ", purchasing" }
        return label
    }
}

#Preview {
    let plans: [SubscriptionPlan] = .previewPlans
    VStack(spacing: 12) {
        SubscriptionPlanCard(plan: plans[0], isRecommended: true, isBusy: false, isPurchasingThis: false, action: {})
        SubscriptionPlanCard(plan: plans[1], isRecommended: false, isBusy: false, isPurchasingThis: false, action: {})
        SubscriptionPlanCard(plan: plans[1], isRecommended: false, isBusy: true, isPurchasingThis: true, action: {})
    }
    .padding()
    .background(Color.warmBackground)
}
