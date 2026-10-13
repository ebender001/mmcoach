//
//  SBARView.swift
//  MMCoach
//
//  Read-only SBAR (Situation, Background, Assessment, Recommendation)
//  summary of the case, shown as one card per letter.
//

import SwiftUI

struct SBARView: View {
    let sbar: SBARSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("SBAR Summary", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(Color.michiganBlueText)

                if let sbar {
                    sectionCard(letter: "S", title: "Situation", text: sbar.situation)
                    sectionCard(letter: "B", title: "Background", text: sbar.background)
                    sectionCard(letter: "A", title: "Assessment", text: sbar.assessment)
                    sectionCard(letter: "R", title: "Recommendation", text: sbar.recommendation)
                } else {
                    Text("No SBAR summary is available for this case.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func sectionCard(letter: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(letter)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.michiganBlueText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.maizeTint))
                Text(title)
                    .font(.headline)
            }
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .polishedCard()
    }
}

#Preview {
    SBARView(sbar: SBARSummary(
        situation: "A 68-year-old man developed hypotension and increasing chest tube output four hours after CABG x3.",
        background: "Uncomplicated CABG x3 with stable early ICU course.",
        assessment: "Findings were consistent with surgical bleeding requiring re-exploration; a bleeding vessel was identified and controlled.",
        recommendation: "Review thresholds for early re-exploration and chest tube output monitoring."
    ))
}
