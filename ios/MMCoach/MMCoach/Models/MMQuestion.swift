//
//  MMQuestion.swift
//  MMCoach
//

import Foundation

/// A single AI-generated follow-up question, as returned in
/// `nextQuestion` by mmCreateCase / mmAnswerQuestion / mmGetCase.
struct MMQuestion: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let category: String
    let reason: String
}
