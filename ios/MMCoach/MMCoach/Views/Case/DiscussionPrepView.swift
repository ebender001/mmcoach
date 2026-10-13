//
//  DiscussionPrepView.swift
//  MMCoach
//

import SwiftUI

struct DiscussionPrepView: View {
    let topics: [DiscussionTopic]
    let questions: [String]
    let caseId: String
    /// Answers already generated for `questions`, keyed by question text.
    let cachedAnswers: [String: String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                topicsSection
                FacultyQuestionsView(questions: questions, caseId: caseId, cachedAnswers: cachedAnswers)
            }
            .padding()
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Be Prepared to Discuss", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .foregroundStyle(Color.michiganBlueText)

            if topics.isEmpty {
                Text("No discussion topics yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topics.enumerated()), id: \.offset) { _, topic in
                    topicCard(topic)
                }
            }
        }
    }

    private func topicCard(_ topic: DiscussionTopic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.topic)
                .font(.headline)
            Text(topic.whyItMatters)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Be prepared to discuss:")
                    .font(.subheadline.weight(.semibold))
                Text(topic.prepareToDiscuss)
                    .font(.subheadline)
            }
            .padding(.top, 4)
        }
        .polishedCard()
    }
}

#Preview {
    NavigationStack {
        DiscussionPrepView(
            topics: [
                DiscussionTopic(topic: "Timing of re-exploration",
                                 whyItMatters: "The patient had persistent bleeding with increasing transfusion requirements.",
                                 prepareToDiscuss: "Thresholds for surgical re-exploration and whether earlier intervention might have been appropriate.")
            ],
            questions: [
                "What prompted the decision to obtain imaging at that point?",
                "At what point would you consider operative re-exploration?"
            ],
            caseId: "preview",
            cachedAnswers: [:]
        )
    }
}
