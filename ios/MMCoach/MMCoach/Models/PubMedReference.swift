//
//  PubMedReference.swift
//  MMCoach
//
//  One PubMed article returned by mmFindReferences -- a live, on-demand
//  lookup for a single reference topic (see ReferenceLookupViewModel).
//  Distinct from ReferenceItem, which is the AI-identified *topic* stored
//  on the case; this is a real, verifiable citation the trainee reviews
//  and picks themselves, never auto-attached to the case.
//

import Foundation

/// One labeled piece of a PubMed abstract (e.g. "Background", "Methods",
/// "Results", "Conclusions") -- see the backend's
/// `pubmedService.js#splitAbstractSections`. `label` is nil for an
/// unstructured abstract, which comes back as a single section.
struct PubMedAbstractSection: Decodable, Hashable {
    let label: String?
    let text: String
}

struct PubMedReference: Decodable, Identifiable, Hashable {
    let pmid: String
    let title: String
    let authors: [String]
    let journal: String?
    let year: String?
    let abstractSections: [PubMedAbstractSection]
    let url: String

    var id: String { pmid }

    /// "Smith J, Doe A, et al." -- trimmed to a readable byline rather
    /// than dumping every listed author for papers with a long author list.
    var authorByline: String? {
        guard !authors.isEmpty else { return nil }
        let shown = authors.prefix(3).joined(separator: ", ")
        return authors.count > 3 ? "\(shown), et al." : shown
    }

    var journalYearLine: String? {
        switch (journal, year) {
        case let (journal?, year?): "\(journal) · \(year)"
        case let (journal?, nil): journal
        case let (nil, year?): year
        case (nil, nil): nil
        }
    }
}

struct PubMedReferenceSearch: Decodable {
    let topic: String
    let results: [PubMedReference]
}
