//
//  RecentCasesEmptyState.swift
//  MMCoach
//

import SwiftUI

/// Shown in place of the Recent Cases list before the trainee has started
/// their first case. Doubles as a brief first-use explanation of the
/// workflow -- a short intro plus three compact steps -- rather than a
/// generic "nothing here" placeholder, since a new trainee otherwise has
/// no idea what "Start a New Case" actually leads to.
struct RecentCasesEmptyState: View {
    private let steps: [(icon: String, title: String, description: String)] = [
        ("mic.fill", "Describe the case", "Dictate or type the clinical summary."),
        ("text.bubble.fill", "Answer focused questions", "Add the details needed to prepare the case."),
        ("doc.text.fill", "Review your presentation", "Prepare your narrative, discussion topics, and likely questions.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No cases yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Start with a brief case summary. M & M Coach will help you clarify the timeline, identify discussion points, and prepare for conference.")
                    .font(.footnote)
                    .foregroundStyle(Color.slateText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HowItWorksStep(icon: step.icon, title: step.title, description: step.description)

                    if index < steps.count - 1 {
                        Divider()
                            .overlay(Color.primary.opacity(0.06))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

#Preview {
    RecentCasesEmptyState()
        .padding()
        .background(Color.warmBackground)
}
