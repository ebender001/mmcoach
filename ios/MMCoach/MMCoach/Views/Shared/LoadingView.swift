//
//  LoadingView.swift
//  MMCoach
//

import SwiftUI

/// A calm, minimal loading state. `rotatingMessages`, when provided, cycles
/// through short status phrases (e.g. "Organizing the case…") without ever
/// implying a fake percentage of completion.
struct LoadingView: View {
    let message: String
    var rotatingMessages: [String] = []

    @State private var rotationIndex = 0

    private let rotationInterval: TimeInterval = 1.6

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(displayedMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: rotationIndex)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard rotatingMessages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(rotationInterval))
                guard !Task.isCancelled else { break }
                rotationIndex = (rotationIndex + 1) % rotatingMessages.count
            }
        }
    }

    private var displayedMessage: String {
        rotatingMessages.isEmpty ? message : rotatingMessages[rotationIndex]
    }
}

#Preview("Static") {
    LoadingView(message: "Loading your case…")
}

#Preview("Rotating") {
    LoadingView(message: "Preparing your M&M case…",
                rotatingMessages: ["Organizing the case", "Identifying discussion points", "Preparing likely questions"])
}
