//
//  PolishedCaseView.swift
//  MMCoach
//
//  Displays the polished M&M narrative, with in-place editing: the pencil
//  button swaps the read-only text for a TextEditor, "Save" persists it
//  via `onSave` (wired to CaseSummaryViewModel.updatePolishedNarrative,
//  which the backend only accepts once the case is `completed`).
//

import SwiftUI

struct PolishedCaseView: View {
    let narrative: String
    let isSaving: Bool
    let onSave: (String) async -> Bool

    @State private var showCopiedConfirmation = false
    @State private var isPresenting = false
    @State private var isEditing: Bool
    @State private var draftText: String
    @State private var saveErrorMessage: String?
    @FocusState private var isEditorFocused: Bool

    init(narrative: String, isSaving: Bool, startEditing: Bool = false, onSave: @escaping (String) async -> Bool) {
        self.narrative = narrative
        self.isSaving = isSaving
        self.onSave = onSave
        _isEditing = State(initialValue: startEditing)
        _draftText = State(initialValue: startEditing ? narrative : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isEditing {
                presentButton
            }

            ScrollView {
                if isEditing {
                    editor
                } else {
                    Text(narrative.isEmpty ? "No narrative yet." : narrative)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    editingToolbarContent
                } else {
                    idleToolbarContent
                }
            }
        }
        .fullScreenCover(isPresented: $isPresenting) {
            PresentationView(narrative: narrative)
        }
        .overlay(alignment: .bottom) {
            if showCopiedConfirmation {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.michiganBlue, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopiedConfirmation = false
                    }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draftText)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .frame(minHeight: 320)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.michiganBlue.opacity(isEditorFocused ? 0.35 : 0.08), lineWidth: isEditorFocused ? 1.5 : 1)
                )

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditorFocused = false }
            }
        }
    }

    @ViewBuilder
    private var idleToolbarContent: some View {
        Button {
            draftText = narrative
            saveErrorMessage = nil
            isEditing = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .disabled(narrative.isEmpty)

        Button {
            UIPasteboard.general.string = narrative
            showCopiedConfirmation = true
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(narrative.isEmpty)
    }

    @ViewBuilder
    private var editingToolbarContent: some View {
        Button("Cancel") {
            isEditorFocused = false
            isEditing = false
            saveErrorMessage = nil
        }
        .disabled(isSaving)

        Button {
            save()
        } label: {
            if isSaving {
                ProgressView()
            } else {
                Text("Save")
                    .fontWeight(.semibold)
            }
        }
        .disabled(isSaving || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var presentButton: some View {
        Button {
            isPresenting = true
        } label: {
            Label("Present", systemImage: "text.magnifyingglass")
        }
        .buttonStyle(.michiganProminent)
        .disabled(narrative.isEmpty)
        .padding()
    }

    private func save() {
        isEditorFocused = false
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            saveErrorMessage = nil
            let succeeded = await onSave(trimmed)
            if succeeded {
                isEditing = false
            } else {
                saveErrorMessage = "Couldn't save your edit. Please try again."
            }
        }
    }
}

#Preview("Read-only") {
    NavigationStack {
        PolishedCaseView(
            narrative: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU, but approximately four hours after arrival became hypotensive with increasing chest tube output…",
            isSaving: false,
            onSave: { _ in true }
        )
    }
}

#Preview("Editing") {
    NavigationStack {
        PolishedCaseView(
            narrative: "A 68-year-old man underwent CABG x3.",
            isSaving: false,
            startEditing: true,
            onSave: { _ in true }
        )
    }
}
