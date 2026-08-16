//
//  MMCase.swift
//  MMCoach
//
//  Client-side representation of an M&M case-preparation session. This is
//  the single Decodable type returned by every BackendService call --
//  mmCreateCase, mmAnswerQuestion, mmFinalizeCase, and mmGetCase all
//  return a subset of these same fields, so one flexible decoder handles
//  all four responses.
//

import Foundation

/// Mirrors the backend's `collecting_information` / `ready_to_finalize` /
/// `completed` state machine (see `schemas/caseStatus.js` in the backend).
enum CaseStatus: String, Codable, Hashable {
    case collectingInformation = "collecting_information"
    case readyToFinalize = "ready_to_finalize"
    case completed = "completed"
}

struct MMCase: Decodable, Identifiable, Hashable {
    let id: String
    var status: CaseStatus
    var nextQuestion: MMQuestion?
    var polishedNarrative: String?
    var discussionPreparation: [DiscussionTopic]
    var likelyFacultyQuestions: [String]
    var references: [ReferenceItem]

    private enum CodingKeys: String, CodingKey {
        case id = "caseId"
        case status
        case nextQuestion
        case polishedNarrative
        case discussionPreparation
        case likelyFacultyQuestions
        case references
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(CaseStatus.self, forKey: .status)
        nextQuestion = try container.decodeIfPresent(MMQuestion.self, forKey: .nextQuestion)
        polishedNarrative = try container.decodeIfPresent(String.self, forKey: .polishedNarrative)
        discussionPreparation = try container.decodeIfPresent([DiscussionTopic].self, forKey: .discussionPreparation) ?? []
        likelyFacultyQuestions = try container.decodeIfPresent([String].self, forKey: .likelyFacultyQuestions) ?? []
        references = try container.decodeIfPresent([ReferenceItem].self, forKey: .references) ?? []
    }

    /// Convenience initializer for previews and tests.
    init(id: String,
         status: CaseStatus,
         nextQuestion: MMQuestion? = nil,
         polishedNarrative: String? = nil,
         discussionPreparation: [DiscussionTopic] = [],
         likelyFacultyQuestions: [String] = [],
         references: [ReferenceItem] = []) {
        self.id = id
        self.status = status
        self.nextQuestion = nextQuestion
        self.polishedNarrative = polishedNarrative
        self.discussionPreparation = discussionPreparation
        self.likelyFacultyQuestions = likelyFacultyQuestions
        self.references = references
    }
}
