//
//  NewCaseView.swift
//  MMCoach
//
//  The trainee describes the case naturally -- by dictating or typing --
//  rather than filling out structured clinical fields.
//

import SwiftUI

struct NewCaseView: View {
    @StateObject private var viewModel = NewCaseViewModel()
    @Binding var path: [AppRoute]
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Describe the case as you would present it at M&M.")
                .font(.title3.weight(.semibold))

            narrativeEditor

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            micButton

            Spacer(minLength: 0)

            continueButton
        }
        .padding()
        .navigationTitle("New Case")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Dictation Unavailable",
               isPresented: dictationErrorBinding,
               presenting: viewModel.dictationErrorMessage) { _ in
            Button("OK") { viewModel.dictationErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var narrativeEditor: some View {
        TextEditor(text: $viewModel.narrativeText)
            .focused($isEditorFocused)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: 220)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .overlay(alignment: .topLeading) {
                if viewModel.narrativeText.isEmpty {
                    Text("A 68-year-old man underwent CABG x3. He was initially stable in the ICU…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
    }

    private var micButton: some View {
        HStack {
            Spacer()
            Button {
                isEditorFocused = false
                Task { await viewModel.toggleDictation() }
            } label: {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .font(.title)
                    .foregroundStyle(viewModel.isRecording ? Color.white : Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(
                        Circle().fill(viewModel.isRecording ? Color.accentColor : Color(.secondarySystemBackground))
                    )
            }
            .accessibilityLabel(viewModel.isRecording ? "Stop dictation" : "Start dictation")
            Spacer()
        }
    }

    private var continueButton: some View {
        Button {
            Task {
                if let created = await viewModel.submit() {
                    path.append(.interview(caseId: created.id, initialCase: created))
                }
            }
        } label: {
            if viewModel.isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canContinue)
    }

    private var dictationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.dictationErrorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.dictationErrorMessage = nil }
            }
        )
    }
}

#Preview {
    NavigationStack {
        NewCaseView(path: .constant([]))
    }
}
