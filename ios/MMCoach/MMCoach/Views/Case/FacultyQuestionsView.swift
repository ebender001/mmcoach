//
//  FacultyQuestionsView.swift
//  MMCoach
//
//  Displays likely faculty questions. Laid out as a simple scannable list
//  today; the per-row structure leaves room for an interactive practice
//  mode (e.g. tap to rehearse an answer) to be added later without
//  reworking this screen.
//

import SwiftUI

struct FacultyQuestionsView: View {
    let questions: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Likely Faculty Questions")
                    .font(.headline)

                if questions.isEmpty {
                    Text("No faculty questions yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                            questionRow(question)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func questionRow(_ question: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Text(question)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
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
