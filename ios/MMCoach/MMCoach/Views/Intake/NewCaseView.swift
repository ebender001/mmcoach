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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    editorCard

                    if !viewModel.spellingSuggestions.isEmpty {
                        Text("Double-check spelling: \(viewModel.spellingSuggestions.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(Color.slateText)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()
                .opacity(0.5)

            continueFooter
        }
        .background(Color.warmBackground)
        .navigationTitle("New Case")
        .navigationBarTitleDisplayMode(.inline)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Describe the case")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Present it as you would at M&M conference.")
                .font(.subheadline)
                .foregroundStyle(Color.slateText)
        }
    }

    /// Boxes the dictate-or-type hint together with the editor and its mic
    /// control so the whole "how to give me the case" unit reads as one
    /// intentional surface, consistent with the Home screen's card style.
    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputModeHint

            DictationEditorView(
                text: $viewModel.narrativeText,
                phase: viewModel.dictationPhase,
                placeholder: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU…",
                minHeight: 200,
                onToggleDictation: { Task { await viewModel.toggleDictation() } }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    /// A single flowing sentence so it wraps naturally as one paragraph on narrow screens.
    private var inputModeHint: some View {
        Text("\(Image(systemName: "mic.fill")) Dictate or \(Image(systemName: "keyboard")) type -- whichever is easier.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.slateText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You can dictate or type the case summary, whichever is easier.")
    }

    private var continueFooter: some View {
        continueButton
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Color.warmBackground)
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
                    .tint(.white)
            } else {
                Text("Continue")
            }
        }
        .buttonStyle(.michiganProminent)
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

    private var phiNoticeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phiNoticeMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.phiNoticeMessage = nil }
            }
        )
    }
}

#Preview {
    NavigationStack {
        NewCaseView(path: .constant([]))
    }
}
