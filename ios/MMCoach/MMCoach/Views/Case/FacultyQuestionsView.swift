//
//  FacultyQuestionsView.swift
//  MMCoach
//
//  Displays likely faculty questions as stacked cards (matching
//  DiscussionPrepView/ReferencesView). Tapping a card opens
//  FacultyQuestionAnswerView, which drafts a model answer for that
//  question live so the trainee can rehearse against something concrete.
//

import SwiftUI

struct FacultyQuestionsView: View {
    let questions: [String]
    let caseId: String

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
                        NavigationLink {
                            FacultyQuestionAnswerView(question: question, caseId: caseId)
                        } label: {
                            questionCard(number: index + 1, question: question)
                        }
                        .buttonStyle(.plain)
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

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .polishedCard()
    }
}

#Preview {
    NavigationStack {
        FacultyQuestionsView(
            questions: [
                "What prompted the decision to obtain imaging at that point?",
                "At what point would you consider operative re-exploration?",
                "Was there an earlier finding that should have changed management?",
                "Would you manage this differently today?"
            ],
            caseId: "preview"
        )
    }
}
