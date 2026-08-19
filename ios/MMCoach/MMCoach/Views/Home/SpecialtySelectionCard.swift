//
//  SpecialtySelectionCard.swift
//  MMCoach
//

import SwiftUI

/// The Home screen's single specialty control: a two-line card (small
/// label above the selected value) rather than a label-plus-picker row,
/// so the selected specialty's full name never has to compete with the
/// trailing chevron for horizontal space at large Dynamic Type sizes.
struct SpecialtySelectionCard: View {
    @Binding var selection: Specialty

    var body: some View {
        Menu {
            Picker("Specialty", selection: $selection) {
                ForEach(Specialty.allCases) { specialty in
                    Text(specialty.displayName).tag(specialty)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Specialty")
                        .font(.caption)
                        .foregroundStyle(Color.slateText)
                    Text(selection.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.slateText)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Specialty, \(selection.displayName)")
        .accessibilityHint("Double tap to change specialty")
    }
}

#Preview {
    SpecialtySelectionCard(selection: .constant(.cardiothoracic))
        .padding()
        .background(Color.warmBackground)
}
