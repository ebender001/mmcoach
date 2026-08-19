//
//  Theme.swift
//  MMCoach
//
//  University of Michigan brand palette (maize and blue) plus the shared
//  button/card/badge styles built on it. Centralized here so every screen
//  looks like one polished app rather than each view inventing its own
//  button/card treatment -- see how DictationEditorView already does this
//  for the dictation control.
//
//  Brand colors are fixed values (not light/dark adaptive) per University
//  of Michigan visual identity guidelines: Blue #00274C, Maize #FFCB05.
//

import SwiftUI
import UIKit

extension Color {
    /// University of Michigan Blue (#00274C), fixed. Use only as an OPAQUE
    /// fill (button backgrounds, solid badge fills) where contrast comes
    /// from the fixed white text/icon on top of it, not from whatever's
    /// behind the view -- the raw navy is too close to the dark-mode system
    /// background to work as a foreground/icon color. For text, icons, or
    /// anything drawn *on* an adaptive background, use `michiganBlueText`.
    static let michiganBlue = Color(red: 0 / 255, green: 39 / 255, blue: 76 / 255)

    /// Michigan Blue, adapted for use as icon/text color in both
    /// appearances: the official navy in light mode, a lighter legible
    /// blue in dark mode (the navy nearly disappears against the near-
    /// black dark-mode background otherwise).
    static let michiganBlueText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 112 / 255, green: 168 / 255, blue: 224 / 255, alpha: 1)
            : UIColor(red: 0 / 255, green: 39 / 255, blue: 76 / 255, alpha: 1)
    })

    /// University of Michigan Maize (#FFCB05). Used sparingly as a
    /// secondary highlight -- active/in-progress states, the dictation
    /// waveform -- never as body text (too low-contrast on white).
    static let maize = Color(red: 255 / 255, green: 203 / 255, blue: 5 / 255)

    /// A soft maize wash safe as a fill behind dark text/icons.
    static let maizeTint = Color.maize.opacity(0.18)

    /// A soft blue wash safe as a fill behind blue text/icons.
    static let michiganBlueTint = Color.michiganBlue.opacity(0.1)

    /// Warm off-white app background for the clinical-editorial screens
    /// (Home). Adapts to the system background in dark mode rather than
    /// forcing a fixed cream tone, which would look muddy at night.
    static let warmBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 250 / 255, green: 248 / 255, blue: 244 / 255, alpha: 1)
    })

    /// Slate-gray secondary text -- quieter than `.secondary` in most
    /// system fonts, used for subtitles and metadata on the Home screen.
    static let slateText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 158 / 255, green: 167 / 255, blue: 176 / 255, alpha: 1)
            : UIColor(red: 90 / 255, green: 99 / 255, blue: 110 / 255, alpha: 1)
    })

    /// Muted teal accent, used sparingly (a single icon tint, not a
    /// primary-action color) to keep the clinical-editorial palette calm.
    static let mutedTeal = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 92 / 255, green: 168 / 255, blue: 163 / 255, alpha: 1)
            : UIColor(red: 58 / 255, green: 125 / 255, blue: 120 / 255, alpha: 1)
    })
}

/// Full-width, filled primary action button (Continue, Submit Answer,
/// Start New Case, Prepare Case).
struct MichiganProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.michiganBlue)
            )
            .shadow(color: isEnabled ? Color.michiganBlue.opacity(0.25) : .clear, radius: 8, y: 4)
            // Dim the whole composed button (fill + text together) rather
            // than just the fill -- fading only the fill blends with
            // whatever's behind it, which can make a "disabled" button
            // nearly disappear against a dark-mode background instead of
            // reading as disabled.
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined secondary action button (Try Again, and other non-primary
/// actions that still need clear affordance).
struct MichiganBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.michiganBlueText)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.michiganBlueText, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MichiganProminentButtonStyle {
    static var michiganProminent: MichiganProminentButtonStyle { MichiganProminentButtonStyle() }
}

extension ButtonStyle where Self == MichiganBorderedButtonStyle {
    static var michiganBordered: MichiganBorderedButtonStyle { MichiganBorderedButtonStyle() }
}

/// A small colored capsule label (case status, category tags).
struct StatusBadge: View {
    let text: String
    let tint: Color
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint))
    }
}

/// The consistent card treatment used for discussion topics, reference
/// rows, and similar content blocks: rounded corners, a soft border, and a
/// faint shadow for depth rather than a flat fill.
struct PolishedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.michiganBlue.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    func polishedCard() -> some View {
        modifier(PolishedCardModifier())
    }
}
