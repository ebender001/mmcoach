//
//  DictationEditorView.swift
//  MMCoach
//
//  A TextEditor with an attached mic-dictation control, shared by the
//  initial case narrative and interview-answer flows -- both compose a
//  DictationController the same way (see NewCaseViewModel /
//  CaseInterviewViewModel), so this view only needs the current phase, a
//  toggle action, and a text binding.
//

import SwiftUI

struct DictationEditorView: View {
    @Binding var text: String
    let phase: DictationPhase
    let placeholder: String
    let minHeight: CGFloat
    let onToggleDictation: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editor
            dictationControl
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: minHeight)
            .disabled(phase != .idle)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.michiganBlue.opacity(isFocused ? 0.35 : 0.08), lineWidth: isFocused ? 1.5 : 1)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty, phase == .idle {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .overlay { editorOverlay }
            .animation(.easeInOut(duration: 0.2), value: phase)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .foregroundStyle(Color.michiganBlueText)
                }
            }
    }

    @ViewBuilder
    private var editorOverlay: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .listening:
            statusOverlay(message: "Listening… don't include patient names, staff or institution names, or dates.") {
                WaveformView()
            }
        case .finishingUp:
            statusOverlay(message: "Finishing up…") {
                ProgressView()
            }
        case .correcting:
            statusOverlay(message: "Checking medical terms…") {
                ProgressView()
            }
        }
    }

    private func statusOverlay(message: String, @ViewBuilder indicator: () -> some View) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.thinMaterial)
            .overlay {
                VStack(spacing: 14) {
                    indicator()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var dictationControl: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button {
                    isFocused = false
                    onToggleDictation()
                } label: {
                    micButtonLabel
                }
                .disabled(phase == .finishingUp || phase == .correcting)
                .accessibilityLabel(micAccessibilityLabel)
                Spacer()
            }
            Text(dictationCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var micButtonLabel: some View {
        let diameter: CGFloat = 64
        switch phase {
        case .idle:
            Image(systemName: "mic")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.michiganBlueText)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .overlay(Circle().strokeBorder(Color.michiganBlueText.opacity(0.25), lineWidth: 1.5))
        case .listening:
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.michiganBlue))
                .overlay(Circle().strokeBorder(Color.maize, lineWidth: 3))
                .shadow(color: Color.michiganBlue.opacity(0.3), radius: 8, y: 3)
        case .finishingUp, .correcting:
            ProgressView()
                .tint(Color.michiganBlueText)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .overlay(Circle().strokeBorder(Color.michiganBlueText.opacity(0.15), lineWidth: 1.5))
        }
    }

    private var micAccessibilityLabel: String {
        switch phase {
        case .idle: return "Start dictation"
        case .listening: return "Stop dictation"
        case .finishingUp: return "Finishing dictation"
        case .correcting: return "Checking medical terms"
        }
    }

    private var dictationCaption: String {
        switch phase {
        case .idle: return "Tap to dictate"
        case .listening: return "Listening — tap to stop"
        case .finishingUp: return "Finishing up…"
        case .correcting: return "Checking medical terms…"
        }
    }
}
