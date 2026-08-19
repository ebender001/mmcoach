//
//  ReferenceLookupView.swift
//  MMCoach
//
//  Reached by tapping a reference card in ReferencesView. Searches PubMed
//  live for the tapped topic and shows up to 5 candidate articles with
//  their abstracts -- the trainee reviews and picks their own sources;
//  nothing here is written back onto the case (see backend README's
//  "References" section for why).
//

import SwiftUI

struct ReferenceLookupView: View {
    @StateObject private var viewModel: ReferenceLookupViewModel

    init(topic: String, searchIntent: String, caseId: String?) {
        _viewModel = StateObject(wrappedValue: ReferenceLookupViewModel(topic: topic, searchIntent: searchIntent, caseId: caseId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView(message: "Searching PubMed…")
            } else if let errorMessage = viewModel.errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await viewModel.search() }
                }
            } else {
                resultsList
            }
        }
        .navigationTitle("PubMed Results")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.search() }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if viewModel.results.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.results) { reference in
                        referenceCard(reference)
                    }
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(viewModel.topic, systemImage: "books.vertical.fill")
                .font(.headline)
                .foregroundStyle(Color.michiganBlueText)
            if !viewModel.searchIntent.isEmpty {
                Text(viewModel.searchIntent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No PubMed results found")
                .font(.subheadline.weight(.medium))
            Text("Try searching PubMed directly with different terms.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func referenceCard(_ reference: PubMedReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reference.title)
                .font(.headline)

            if let byline = reference.authorByline {
                Text(byline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let journalYearLine = reference.journalYearLine {
                Text(journalYearLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if reference.abstractSections.isEmpty {
                Text("No abstract available.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.top, 4)
            } else {
                abstractView(reference.abstractSections)
            }

            Link(destination: URL(string: reference.url) ?? URL(string: "https://pubmed.ncbi.nlm.nih.gov")!) {
                Label("View on PubMed", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
            }
            .padding(.top, 4)
        }
        .polishedCard()
    }

    /// Renders each abstract section as its own small block -- a caps
    /// "eyebrow" label (Background/Methods/Results/Conclusions, etc.)
    /// above its paragraph -- rather than one dense run of text. An
    /// unstructured abstract (single `label: nil` section) just renders
    /// as one plain paragraph, same as before.
    private func abstractView(_ sections: [PubMedAbstractSection]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 3) {
                    if let label = section.label {
                        Text(label.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.michiganBlueText)
                    }
                    Text(section.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.top, 4)
    }
}

// BackendService is a static, non-mockable enum (see its own header
// comment), so unlike the sibling Case-section views (which just take
// already-loaded plain data) this preview triggers a real Cloud Function
// call. Parse isn't configured in the preview process, so it renders the
// error state rather than results -- still useful to check that state's
// layout, just not a like-for-like results preview.
#Preview("Results") {
    NavigationStack {
        ReferenceLookupView(
            topic: "Postoperative bleeding after cardiac surgery",
            searchIntent: "Current guideline or high-quality evidence regarding indications and timing for surgical re-exploration.",
            caseId: "preview"
        )
    }
}
