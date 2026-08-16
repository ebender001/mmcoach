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

    var body: some View {
        ScrollView {
            Text(narrative.isEmpty ? "No narrative yet." : narrative)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
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
        .overlay(alignment: .bottom) {
            if showCopiedConfirmation {
                Text("Copied")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopiedConfirmation = false
                    }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PolishedCaseView(narrative: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU, but approximately four hours after arrival became hypotensive with increasing chest tube output…")
    }
}
