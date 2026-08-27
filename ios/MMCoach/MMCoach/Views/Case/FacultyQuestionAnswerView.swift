//
//  FacultyQuestionAnswerView.swift
//  MMCoach
//
//  Reached by tapping a question card in FacultyQuestionsView. Drafts a
//  model answer for that question, grounded in the case, so the trainee has
//  something concrete to rehearse against.
//

import SwiftUI

struct FacultyQuestionAnswerView: View {
    @StateObject private var viewModel: FacultyQuestionAnswerViewModel

    init(question: String, caseId: String) {
        _viewModel = StateObject(wrappedValue: FacultyQuestionAnswerViewModel(question: question, caseId: caseId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(viewModel.question, systemImage: "person.fill.questionmark")
                    .font(.headline)
                    .foregroundStyle(Color.michiganBlueText)

                if viewModel.isLoading {
                    LoadingView(message: "Drafting an answer…")
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(message: errorMessage) {
                        Task { await viewModel.loadAnswer() }
                    }
                } else if let answer = viewModel.answer {
                    Text(answer)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .polishedCard()
                }
            }
            .padding()
        }
        .navigationTitle("Rehearse Answer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadAnswer() }
    }
}

// BackendService is a static, non-mockable enum, so unlike the sibling
// Case-section views (which just take already-loaded plain data) this
// preview triggers a real Cloud Function call. Parse isn't configured in
// the preview process, so it renders the error state rather than an
// answer -- still useful to check that state's layout, just not a
// like-for-like results preview.
#Preview("Answer") {
    NavigationStack {
        FacultyQuestionAnswerView(
            question: "What prompted the decision to obtain imaging at that point?",
            caseId: "preview"
        )
    }
}
