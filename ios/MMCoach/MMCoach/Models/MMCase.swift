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

/// One PubMed lookup the backend has already run for a reference topic on
/// this case, returned inline on the case so the client can skip
/// `mmFindReferences` entirely for a topic it's already searched. Only
/// `results` is decoded -- `query`/`cachedAt` are backend-internal detail
/// the client has no use for.
struct CachedReferenceLookup: Decodable, Hashable {
    let results: [PubMedReference]
}

struct MMCase: Decodable, Identifiable, Hashable {
    let id: String
    var status: CaseStatus
    var nextQuestion: MMQuestion?
    var polishedNarrative: String?
    /// The narrative as typed or dictated when the case was created. Only
    /// returned by `mmGetCase`, so nil on snapshots from create/answer.
    var originalNarrative: String?
    /// SBAR summary generated at finalize; nil on older cases.
    var sbar: SBARSummary?
    var discussionPreparation: [DiscussionTopic]
    var likelyFacultyQuestions: [String]
    var references: [ReferenceItem]
    /// Faculty questions already answered on this case, keyed by the
    /// question's exact text -- lets the client show a cached answer
    /// (see FacultyQuestionAnswerViewModel) without calling
    /// `mmAnswerFacultyQuestion` again for a question already answered.
    var facultyQuestionAnswers: [String: String]
    /// Reference topics already looked up on this case, keyed by topic --
    /// lets the client skip `mmFindReferences` for a topic already
    /// searched (see ReferenceLookupViewModel).
    var referenceLookups: [String: CachedReferenceLookup]

    private enum CodingKeys: String, CodingKey {
        case id = "caseId"
        case status
        case nextQuestion
        case polishedNarrative
        case originalNarrative
        case sbar
        case discussionPreparation
        case likelyFacultyQuestions
        case references
        case facultyQuestionAnswers
        case referenceLookups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(CaseStatus.self, forKey: .status)
        nextQuestion = try container.decodeIfPresent(MMQuestion.self, forKey: .nextQuestion)
        polishedNarrative = try container.decodeIfPresent(String.self, forKey: .polishedNarrative)
        originalNarrative = try container.decodeIfPresent(String.self, forKey: .originalNarrative)
        sbar = try container.decodeIfPresent(SBARSummary.self, forKey: .sbar)
        discussionPreparation = try container.decodeIfPresent([DiscussionTopic].self, forKey: .discussionPreparation) ?? []
        likelyFacultyQuestions = try container.decodeIfPresent([String].self, forKey: .likelyFacultyQuestions) ?? []
        references = try container.decodeIfPresent([ReferenceItem].self, forKey: .references) ?? []
        facultyQuestionAnswers = try container.decodeIfPresent([String: String].self, forKey: .facultyQuestionAnswers) ?? [:]
        referenceLookups = try container.decodeIfPresent([String: CachedReferenceLookup].self, forKey: .referenceLookups) ?? [:]
    }

    /// Convenience initializer for previews and tests.
    init(id: String,
         status: CaseStatus,
         nextQuestion: MMQuestion? = nil,
         polishedNarrative: String? = nil,
         sbar: SBARSummary? = nil,
         discussionPreparation: [DiscussionTopic] = [],
         likelyFacultyQuestions: [String] = [],
         references: [ReferenceItem] = [],
         facultyQuestionAnswers: [String: String] = [:],
         referenceLookups: [String: CachedReferenceLookup] = [:]) {
        self.id = id
        self.status = status
        self.nextQuestion = nextQuestion
        self.polishedNarrative = polishedNarrative
        self.sbar = sbar
        self.discussionPreparation = discussionPreparation
        self.likelyFacultyQuestions = likelyFacultyQuestions
        self.references = references
        self.facultyQuestionAnswers = facultyQuestionAnswers
        self.referenceLookups = referenceLookups
    }
}
