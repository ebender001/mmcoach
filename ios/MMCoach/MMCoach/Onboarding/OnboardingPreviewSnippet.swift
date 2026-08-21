//
//  OnboardingPreviewSnippet.swift
//  MMCoach
//
//  Non-interactive illustrations of the real screens each onboarding page
//  is describing -- built from the same colors/type/icon treatment as the
//  actual components (NewCaseActionCard, DictationEditorView,
//  HowItWorksStep), not a separate visual language. None of these are
//  live controls: no button here starts dictation, submits anything, or
//  can request a permission -- onboarding must never trigger that.
//

import SwiftUI

struct OnboardingPreviewSnippet: View {
    let kind: OnboardingPreviewKind

    var body: some View {
        switch kind {
        case .none:
            EmptyView()
        case .startCaseButton:
            // No "PREVIEW" label here -- the welcome page labels the whole
            // flow as a preview once, in its own subtitle (see
            // OnboardingPageModel.all's welcome page), so tagging this one
            // illustration too would be redundant.
            content
        case .dictateCard, .questionCard, .howItWorksRecap:
            VStack(alignment: .leading, spacing: 6) {
                previewLabel
                content
            }
        }
    }

    /// Faithfully mimicking the real buttons/controls (right down to the
    /// "Tap to dictate" mic) is exactly what makes these illustrations
    /// useful -- but it also means they can be mistaken for live controls.
    /// This is the one thing standing between a trainee and tapping a
    /// "Start a New Case" button that doesn't go anywhere.
    private var previewLabel: some View {
        Text("PREVIEW")
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.slateText)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .none:
            EmptyView()
        case .startCaseButton:
            startCaseButton
        case .dictateCard:
            dictateCard
        case .questionCard:
            questionCard
        case .howItWorksRecap:
            howItWorksRecap
        }
    }

    // MARK: - Page 1: Home's "Start a New Case" button

    private var startCaseButton: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.16)))

            VStack(alignment: .leading, spacing: 1) {
                Text("Start a New Case")
                    .font(.subheadline.weight(.semibold))
                Text("Dictate or enter a clinical case summary")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.michiganBlue))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the Start a New Case button")
    }

    // MARK: - Page 2: the dictate/type card from New Case

    private var dictateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            dictateInputPreview(placeholder: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU…")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the case dictation card")
    }

    // MARK: - Page 3: one interview question card

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedTeal)
                Text("When did the postoperative bleeding become apparent?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            // Answering a question uses the same dictate-or-type input as
            // the initial case narrative (DictationEditorView is shared by
            // both flows), so this preview shows the same hint row,
            // placeholder, and mic button as dictateCard, not just the
            // question itself.
            dictateInputPreview(placeholder: "Post-op day 2, once the patient became tachycardic…")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of an interview question card")
    }

    /// The hint row, placeholder text, and mic button shared by
    /// `dictateCard` and `questionCard` -- both illustrate the same real
    /// dictate-or-type input (DictationEditorView), just for different
    /// text (the initial narrative vs. one interview answer).
    private func dictateInputPreview(placeholder: String) -> some View {
        Group {
            Text("\(Image(systemName: "mic.fill")) Dictate or \(Image(systemName: "keyboard")) type -- whichever is easier.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.slateText)

            Text(placeholder)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))

            VStack(spacing: 6) {
                Image(systemName: "mic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.michiganBlueText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                    .overlay(Circle().strokeBorder(Color.michiganBlueText.opacity(0.25), lineWidth: 1.5))
                Text("Tap to dictate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page 4: the real "how it works" recap

    private var howItWorksRecap: some View {
        VStack(spacing: 12) {
            HowItWorksStep(icon: "mic.fill", title: "Describe the case", description: "Dictate or type the clinical summary.")
            Divider().overlay(Color.primary.opacity(0.06))
            HowItWorksStep(icon: "text.bubble.fill", title: "Answer focused questions", description: "Add the details needed to prepare the case.")
            Divider().overlay(Color.primary.opacity(0.06))
            HowItWorksStep(icon: "doc.text.fill", title: "Review your presentation", description: "Prepare your narrative, discussion topics, and likely questions.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

#Preview("Start case button") {
    OnboardingPreviewSnippet(kind: .startCaseButton).padding().background(Color.warmBackground)
}

#Preview("Dictate card") {
    OnboardingPreviewSnippet(kind: .dictateCard).padding().background(Color.warmBackground)
}

#Preview("Question card") {
    OnboardingPreviewSnippet(kind: .questionCard).padding().background(Color.warmBackground)
}

#Preview("How it works recap") {
    OnboardingPreviewSnippet(kind: .howItWorksRecap).padding().background(Color.warmBackground)
}
