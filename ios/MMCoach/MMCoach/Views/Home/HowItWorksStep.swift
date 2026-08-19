//
//  HowItWorksStep.swift
//  MMCoach
//

import SwiftUI

/// One row of the empty-state "how it works" walkthrough: a small muted
/// icon plus a title/description pair. Compact by design -- these are
/// stacked rows inside the empty-state card, not standalone cards.
struct HowItWorksStep: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.mutedTeal)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.mutedTeal.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.slateText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 10) {
        HowItWorksStep(icon: "mic.fill", title: "Describe the case", description: "Dictate or type the clinical summary.")
        HowItWorksStep(icon: "text.bubble.fill", title: "Answer focused questions", description: "Add the details needed to prepare the case.")
        HowItWorksStep(icon: "doc.text.fill", title: "Review your presentation", description: "Prepare your narrative, discussion topics, and likely questions.")
    }
    .padding()
    .background(Color.warmBackground)
}
