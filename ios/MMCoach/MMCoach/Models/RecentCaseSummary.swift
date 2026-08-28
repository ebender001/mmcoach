//
//  RecentCaseSummary.swift
//  MMCoach
//
//  One row in the Home screen's "Recent Cases" list, as returned by
//  mmListCases. The backend is the single source of truth for which
//  cases exist and their status -- MMCoach no longer keeps its own local
//  index of them (see HiddenCaseIdsStore for the one thing that's still
//  local: which case ids this device has swiped away from the list).
//

import Foundation

struct RecentCaseSummary: Decodable, Identifiable, Hashable {
    let id: String
    var title: String
    let createdAt: Date
    var status: CaseStatus

    private enum CodingKeys: String, CodingKey {
        case id = "caseId"
        case title
        case createdAt
        case status
    }
}
