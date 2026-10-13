//
//  AIDataConsentView.swift
//  MMCoach
//
//  One-time gate presented before the trainee's first case: discloses
//  exactly what case data is sent to OpenAI, a third-party AI service,
//  and requires an explicit "I Agree" before proceeding. Presented as a
//  sheet from HomeView, gated by HomeViewModel.startNewCase() -- every
//  network call that carries case text (dictation correction, case
//  creation, interview answers, finalization, reference lookups, faculty
//  Q&A) is only reachable after passing through that gate.
//

import SwiftUI

struct AIDataConsentView: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerIcon

                    Text("How Your Case Data Is Used")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("To help you prepare each case, M & M Coach sends parts of it to OpenAI, a third-party AI service, for dictation correction, follow-up questions, and your polished narrative and discussion prep.")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What's sent to OpenAI")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        dataRow("Your dictated or typed case narrative")
                        dataRow("Your answers to follow-up questions")
                        dataRow("Case details used for reference lookups and faculty-question answers")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .polishedCard()

                    Text("Before anything is sent, M & M Coach automatically screens the text on your device and removes names, dates, and other identifying details it detects. Even so, never dictate or type real patient or staff identifiers.")
                        .font(.footnote)
                        .foregroundStyle(Color.slateText)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("Read our full Privacy Policy", destination: LegalLinks.privacyPolicy)
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                Button("I Agree & Continue", action: onAgree)
                    .buttonStyle(.michiganProminent)
                Button("Not Now", action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slateText)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color.warmBackground.ignoresSafeArea())
    }

    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(Color.mutedTeal.opacity(0.14))
                .frame(width: 56, height: 56)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.mutedTeal)
        }
        .accessibilityHidden(true)
    }

    private func dataRow(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.michiganBlueText)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.warmBackground
        .sheet(isPresented: .constant(true)) {
            AIDataConsentView(onAgree: {}, onCancel: {})
        }
}
