//
//  WaveformView.swift
//  MMCoach
//
//  A lightweight "listening" animation for the dictation recording state.
//  Bars pulse with staggered timing to suggest live audio -- they aren't
//  driven by actual microphone input levels.
//

import SwiftUI

struct WaveformView: View {
    private let barHeights: [CGFloat] = [14, 26, 34, 22, 30, 16]
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(barHeights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.maize)
                    .frame(width: 4, height: isAnimating ? barHeights[index] : 8)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
        .frame(height: barHeights.max())
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

#Preview {
    WaveformView()
        .padding()
}
