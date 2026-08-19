//
//  ReferencesView.swift
//  MMCoach
//
//  In the MVP the backend identifies reference *topics* to look up, not
//  verified citations -- this view must not present them as if they were.
//  Tapping a card opens ReferenceLookupView, which searches PubMed live
//  for that topic so the trainee can review and pick real citations.
//

import SwiftUI

struct ReferencesView: View {
    let references: [ReferenceItem]
    let caseId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("References", systemImage: "books.vertical.fill")
                    .font(.headline)
                    .foregroundStyle(Color.michiganBlueText)

                if references.isEmpty {
                    Text("No reference topics yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                        NavigationLink {
                            ReferenceLookupView(topic: reference.topic, searchIntent: reference.searchIntent, caseId: caseId)
                        } label: {
                            referenceRow(reference)
                        }
                        .buttonStyle(.plain)
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
                .foregroundStyle(.primary)

            Label {
                Text(reference.searchIntent)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                if let citation = reference.citation, reference.verified {
                    Text(citation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not yet verified")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }

                Spacer()

                Label("Search PubMed", systemImage: "chevron.right")
                    .labelStyle(.trailingIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.michiganBlueText)
            }
            .padding(.top, 2)
        }
        .polishedCard()
    }
}

/// Puts the icon *after* the title (e.g. "Search PubMed ›") -- the
/// default `Label` always puts the icon first, which reads oddly for a
/// trailing chevron-style disclosure hint.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

private extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

#Preview {
    NavigationStack {
        ReferencesView(
            references: [
                ReferenceItem(topic: "Postoperative bleeding after cardiac surgery",
                              searchIntent: "Current guideline or high-quality evidence regarding indications and timing for surgical re-exploration.",
                              citation: nil,
                              verified: false)
            ],
            caseId: "preview"
        )
    }
}
