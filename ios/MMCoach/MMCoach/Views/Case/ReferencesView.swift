//
//  ReferencesView.swift
//  MMCoach
//
//  In the MVP the backend identifies reference *topics* to look up, not
//  verified citations -- this view must not present them as if they were.
//  The row layout leaves room for real citations (PubMed links, authors,
//  journal, publication info) once retrieval/verification exists.
//

import SwiftUI

struct ReferencesView: View {
    let references: [ReferenceItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("References")
                    .font(.headline)

                if references.isEmpty {
                    Text("No reference topics yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                        referenceRow(reference)
                    }
                }
            }
            .padding()
        }
    }

    private func referenceRow(_ reference: ReferenceItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reference.topic)
                .font(.headline)

            Label {
                Text(reference.searchIntent)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let citation = reference.citation, reference.verified {
                Text(citation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Evidence not yet located")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    ReferencesView(references: [
        ReferenceItem(topic: "Postoperative bleeding after cardiac surgery",
                      searchIntent: "Current guideline or high-quality evidence regarding indications and timing for surgical re-exploration.",
                      citation: nil,
                      verified: false)
    ])
}
