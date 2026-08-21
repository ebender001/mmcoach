//
//  QuestionCardView.swift
//  MMCoach
//
//  Presents a single AI follow-up question. Deliberately plain text, not a
//  card with a background/border -- the answer field right below it (see
//  DictationEditorView) is the only thing on this screen that should read
//  as "you can put content here." Boxing the question the same way made
//  the two hard to tell apart at a glance.
//

import SwiftUI

struct QuestionCardView: View {
    let question: MMQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("I need one more detail:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(question.text)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    QuestionCardView(question: MMQuestion(id: "q1",
                                           text: "When did the hypotension begin relative to the patient's arrival in the ICU?",
                                           category: "timing",
                                           reason: "Timing narrows the differential."))
    .padding()
}
