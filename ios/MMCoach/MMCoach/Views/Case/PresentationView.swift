//
//  PresentationView.swift
//  MMCoach
//
//  Full-screen, decluttered narrative display for actually presenting at
//  M&M -- no segmented control, toolbar, or nav chrome competing for space,
//  just large text a trainee can read at a glance while talking. Text size
//  is adjustable and remembered across cases (podium lighting/distance
//  varies), separate from the compact reading view in PolishedCaseView.
//

import SwiftUI

struct PresentationView: View {
    let narrative: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("MMCoach.presentationFontSize") private var fontSize: Double = 28

    private let minFontSize: Double = 20
    private let maxFontSize: Double = 44
    private let fontStep: Double = 2

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(narrative.isEmpty ? "No narrative yet." : narrative)
                    .font(.system(size: fontSize, design: .serif))
                    .lineSpacing(fontSize * 0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .navigationTitle("Presenting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        fontSize = max(minFontSize, fontSize - fontStep)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .disabled(fontSize <= minFontSize)

                    Button {
                        fontSize = min(maxFontSize, fontSize + fontStep)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .disabled(fontSize >= maxFontSize)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PresentationView(narrative: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU, but approximately four hours after arrival became hypotensive with increasing chest tube output. He was resuscitated with blood products and returned to the operating room, where a bleeding vessel was identified and controlled.")
}
