//
//  OnboardingPage.swift
//  MMCoach
//
//  One page of first-launch onboarding (see OnboardingView). Scrollable so
//  the largest Dynamic Type sizes never clip content -- they just make the
//  page taller/scrollable instead.
//

import SwiftUI

struct OnboardingPage: View {
    let model: OnboardingPageModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                icon

                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(model.title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        if let subtitle = model.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.slateText)
                        }
                    }

                    Text(model.bodyText)
                        .font(.body)
                        .foregroundStyle(Color.slateText)
                        .multilineTextAlignment(.center)
                }

                if model.preview != .none {
                    OnboardingPreviewSnippet(kind: model.preview)
                }

                if !model.footnotes.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(model.footnotes, id: \.text) { footnote in
                            footnoteView(footnote)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func footnoteView(_ footnote: OnboardingFootnote) -> some View {
        switch footnote.style {
        case .highlight:
            Text(footnote.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.michiganBlueText)
                .multilineTextAlignment(.center)
        case .reminder:
            // Same lock-icon caption treatment as PrivacyReminder on Home
            // -- it's the same warning, so it should look like it.
            Label {
                Text(footnote.text)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(Color.slateText)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .combine)
        }
    }

    /// Modest, on-theme -- a single restrained SF Symbol in a soft teal
    /// circle, matching PaywallView's header treatment. Purely decorative,
    /// so it's hidden from VoiceOver; the title already conveys the page.
    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.mutedTeal.opacity(0.14))
                .frame(width: 96, height: 96)
            Image(systemName: model.symbolName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.mutedTeal)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Welcome") {
    OnboardingPage(model: OnboardingPageModel.all[0])
        .background(Color.warmBackground)
}

#Preview("Describe the case") {
    OnboardingPage(model: OnboardingPageModel.all[1])
        .background(Color.warmBackground)
}

#Preview("Clarify the details") {
    OnboardingPage(model: OnboardingPageModel.all[2])
        .background(Color.warmBackground)
}

#Preview("Prepare for discussion") {
    OnboardingPage(model: OnboardingPageModel.all[3])
        .background(Color.warmBackground)
}

#Preview("Dynamic Type - XXL") {
    OnboardingPage(model: OnboardingPageModel.all[3])
        .background(Color.warmBackground)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
