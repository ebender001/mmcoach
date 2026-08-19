//
//  PrivacyReminder.swift
//  MMCoach
//

import SwiftUI

/// Subdued helper text below the "Start a New Case" action, reminding the
/// trainee to keep the dictated/typed summary de-identified. Intentionally
/// quiet styling -- it must stay visible without competing with the
/// primary action above it.
struct PrivacyReminder: View {
    var body: some View {
        Label {
            Text("Do not include patient identifiers, dates, or locations.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundStyle(Color.slateText)
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PrivacyReminder()
        .padding()
        .background(Color.warmBackground)
}
