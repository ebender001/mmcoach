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

    /// The editor needs a genuine upper bound to hand `DictationEditorView`
    /// (which fills whatever it's given and scrolls long text internally
    /// -- see that view's header) -- a plain `VStack` with no enclosing
    /// `.frame(maxHeight: .infinity)` or `ScrollView` doesn't impose one:
    /// SwiftUI will happily render content taller than the screen and let
    /// the excess extend off the bottom, invisible, which is exactly what
    /// a long dictated answer did. Splitting into a flexible top region
    /// (bounded, like NewCaseView's) and a fixed bottom region (submit
    /// button, always visible) fixes that.
    private func interviewContent(question: MMQuestion) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                QuestionCardView(question: question)

                DictationEditorView(
                    text: $viewModel.answerText,
                    phase: viewModel.dictationPhase,
                    placeholder: "Answer as you would explain it out loud…",
                    minHeight: 120,
                    onToggleDictation: { Task { await viewModel.toggleDictation() } }
                )
                .frame(maxHeight: .infinity)
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.spellingSuggestions.isEmpty {
                    Text("Double-check spelling: \(viewModel.spellingSuggestions.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await viewModel.submitAnswer() }
                } label: {
                    if viewModel.isSubmittingAnswer {
                        ProgressView().tint(.white)
                    } else {
                        Text("Submit Answer")
                    }
                }
                .buttonStyle(.michiganProminent)
                .disabled(!viewModel.canSubmitAnswer)
            }
            .padding([.horizontal, .bottom])
        }
        .alert("Dictation Unavailable",
               isPresented: dictationErrorBinding,
               presenting: viewModel.dictationErrorMessage) { _ in
            Button("OK") { viewModel.dictationErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Possible Patient Information Removed",
               isPresented: phiNoticeBinding,
               presenting: viewModel.phiNoticeMessage) { _ in
            Button("OK") { viewModel.phiNoticeMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var dictationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.dictationErrorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.dictationErrorMessage = nil }
            }
        )
    }

    private var phiNoticeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phiNoticeMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.phiNoticeMessage = nil }
            }
        )
    }

    private var readyToFinalizeContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.michiganBlueText)

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
                    Text("Prepare Case")
                }
                .buttonStyle(.michiganProminent)
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
