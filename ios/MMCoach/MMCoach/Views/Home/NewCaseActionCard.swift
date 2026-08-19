//
//  NewCaseActionCard.swift
//  MMCoach
//

import SwiftUI

/// The Home screen's primary call to action. Deliberately not built on
/// `.michiganProminent` (a full-width filled button meant for form
/// submission) -- this needs a two-line title/subtitle plus a leading
/// icon, so it gets its own compact card-style button instead.
struct NewCaseActionCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a New Case")
                        .font(.body.weight(.semibold))
                    Text("Dictate or enter a clinical case summary")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.michiganBlue)
            )
        }
        .buttonStyle(NewCaseActionButtonStyle())
        .accessibilityLabel("Start a New Case")
        .accessibilityHint("Dictate or enter a clinical case summary")
    }
}

/// A clear, modest pressed state (slight dim + scale) without the heavier
/// shadow `MichiganProminentButtonStyle` uses -- this card sits directly
/// on the warm background, so a big drop shadow would read as "generic
/// dashboard tile" rather than calm and editorial.
private struct NewCaseActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NewCaseActionCard(action: {})
        .padding()
        .background(Color.warmBackground)
}
