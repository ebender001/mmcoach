//
//  ReferenceItem.swift
//  MMCoach
//

import Foundation

/// A literature/guideline topic identified by the backend as relevant to
/// the case. In the MVP the backend only identifies *what* should be
/// looked up -- `citation` is always nil and `verified` is always false.
/// The fields already exist so real citations (PubMed links, authors,
/// journals, publication info) can be attached by a future backend
/// feature without changing this model's shape.
struct ReferenceItem: Codable, Hashable {
    let topic: String
    let searchIntent: String
    let citation: String?
    let verified: Bool
}
