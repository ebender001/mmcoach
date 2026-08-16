//
//  CaseInterviewView.swift
//  MMCoach
//
//  Presents the interview loop: one AI question, one typed answer, one
//  submit action -- repeated until the backend reports the case is ready
//  to finalize. This view never decides that on its own.
//

import SwiftUI

struct CaseInterviewView: View {
    @StateObject private var viewModel: CaseInterviewViewModel
    @Binding var path: [AppRoute]
    @FocusState private var isAnswerFieldFocused: Bool

    init(viewModel: @autoclosure @escaping () -> CaseInterviewViewModel, path: Binding<[AppRoute]>) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _path = path
    }

    var body: some View {
        Group {
            if viewModel.isLoadingCase {
                LoadingView(message: "Loading your case…")
            } else if viewModel.status == .collectingInformation, let question = viewModel.currentQuestion {
                interviewContent(question: question)
            } else {
                readyToFinalizeContent
            }
        }
        .navigationTitle("Preparing Your Case")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadIfNeeded() }
    }

    private func interviewContent(question: MMQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            QuestionCardView(question: question)

            TextEditor(text: $viewModel.answerText)
                .focused($isAnswerFieldFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button {
                isAnswerFieldFocused = false
                Task { await viewModel.submitAnswer() }
            } label: {
                if viewModel.isSubmittingAnswer {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Submit Answer").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSubmitAnswer)
        }
        .padding()
    }

    private var readyToFinalizeContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Your case is ready to prepare.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if viewModel.isFinalizing {
                LoadingView(message: "Preparing your M&M case…",
                            rotatingMessages: ["Organizing the case",
                                                "Identifying discussion points",
                                                "Preparing likely questions"])
                .frame(height: 160)
            } else {
                Button {
                    Task {
                        if let finalized = await viewModel.finalize() {
                            path.append(.summary(caseId: finalized.id, initialCase: finalized))
                        }
                    }
                } label: {
                    Text("Prepare Case").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }
}

#Preview("Question") {
    NavigationStack {
        CaseInterviewView(
            viewModel: CaseInterviewViewModel(
                caseId: "preview",
                initialCase: MMCase(id: "preview",
                                     status: .collectingInformation,
                                     nextQuestion: MMQuestion(id: "q1",
                                                               text: "When did the hypotension begin relative to the patient's arrival in the ICU?",
                                                               category: "timing",
                                                               reason: "Timing matters."))
            ),
            path: .constant([])
        )
    }
}

#Preview("Ready to Finalize") {
    NavigationStack {
        CaseInterviewView(
            viewModel: CaseInterviewViewModel(
                caseId: "preview",
                initialCase: MMCase(id: "preview", status: .readyToFinalize)
            ),
            path: .constant([])
        )
    }
}
