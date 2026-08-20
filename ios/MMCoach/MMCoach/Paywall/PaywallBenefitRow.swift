//
//  PaywallBenefitRow.swift
//  MMCoach
//
//  One compact benefit line on PaywallView -- a restrained SF Symbol plus
//  a title/detail pair, matching the app's existing icon-in-a-column card
//  language (see NewCaseActionCard) rather than a decorative illustration.
//

import SwiftUI

struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.michiganBlueText)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.slateText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
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
    .padding()
    .background(Color.warmBackground)
}
