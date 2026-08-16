//
//  RecentCaseRecord.swift
//  MMCoach
//
//  Local-only metadata for the Home screen's "Recent Cases" list. The
//  backend does not currently expose a case-listing Cloud Function, so
//  MMCoach keeps a small local index of cases the trainee has started on
//  this device, refreshed from Back4App on demand for the case itself.
//

import Foundation

struct RecentCaseRecord: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let createdAt: Date
    var status: CaseStatus
}
