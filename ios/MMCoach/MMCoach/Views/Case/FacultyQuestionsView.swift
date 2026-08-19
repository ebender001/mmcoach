//
//  FacultyQuestionsView.swift
//  MMCoach
//
//  Displays likely faculty questions as stacked cards (matching
//  DiscussionPrepView/ReferencesView). The per-card structure leaves room
//  for an interactive practice mode (e.g. tap to rehearse an answer) to
//  be added later without reworking this screen.
//

import SwiftUI

struct FacultyQuestionsView: View {
    let questions: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Likely Faculty Questions", systemImage: "person.fill.questionmark")
                    .font(.headline)
                    .foregroundStyle(Color.michiganBlueText)

                if questions.isEmpty {
                    Text("No faculty questions yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        questionCard(number: index + 1, question: question)
                    }
                }
            }
            .padding()
        }
    }

    private func questionCard(number: Int, question: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.michiganBlueText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.maizeTint))
                .padding(.top, 1)
            Text(question)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .polishedCard()
    }
}

#Preview {
    FacultyQuestionsView(questions: [
        "What prompted the decision to obtain imaging at that point?",
        "At what point would you consider operative re-exploration?",
        "Was there an earlier finding that should have changed management?",
        "Would you manage this differently today?"
    ])
}
