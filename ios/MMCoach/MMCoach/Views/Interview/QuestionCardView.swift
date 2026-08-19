//
//  QuestionCardView.swift
//  MMCoach
//
//  Presents a single AI follow-up question. Deliberately not a chat
//  bubble -- this is a structured "question -> answer field -> submit"
//  workflow, not a messaging interface.
//

import SwiftUI

struct QuestionCardView: View {
    let question: MMQuestion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.maize)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("I need one more detail:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(question.text)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    QuestionCardView(question: MMQuestion(id: "q1",
                                           text: "When did the hypotension begin relative to the patient's arrival in the ICU?",
                                           category: "timing",
                                           reason: "Timing narrows the differential."))
    .padding()
}
