//
//  PolishedCaseView.swift
//  MMCoach
//
//  Displays the polished M&M narrative. Editing is not fully implemented
//  in this first pass, but the toolbar/action architecture is in place so
//  real editing can be added without restructuring this screen.
//

import SwiftUI

struct PolishedCaseView: View {
    let narrative: String

    @State private var showCopiedConfirmation = false
    @State private var isPresenting = false

    var body: some View {
        VStack(spacing: 0) {
            presentButton

            ScrollView {
                Text(narrative.isEmpty ? "No narrative yet." : narrative)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    // Full editing is a future enhancement; this screen's
                    // structure already supports adding it here.
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(true)

                Button {
                    UIPasteboard.general.string = narrative
                    showCopiedConfirmation = true
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(narrative.isEmpty)
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
}

#Preview {
    NavigationStack {
        PolishedCaseView(narrative: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU, but approximately four hours after arrival became hypotensive with increasing chest tube output…")
    }
}
