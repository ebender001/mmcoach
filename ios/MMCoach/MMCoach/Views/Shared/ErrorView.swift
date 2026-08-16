//
//  ErrorView.swift
//  MMCoach
//

import SwiftUI

/// A concise, non-technical error state with an optional retry action.
/// Never shown with raw Parse/OpenAI/server error text -- callers pass a
/// message already produced by `BackendError`/`LocalizedError`.
struct ErrorView: View {
    let message: String
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorView(message: "MMCoach couldn't reach the server. Check your connection and try again.") {}
}
