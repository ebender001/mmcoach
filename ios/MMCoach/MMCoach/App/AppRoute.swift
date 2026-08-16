//
//  AppRoute.swift
//  MMCoach
//
//  Typed navigation destinations for the app's single NavigationStack.
//

import Foundation

/// Destinations reachable from `HomeView`'s `NavigationStack`.
///
/// `MMCoach` uses one root stack rather than a `TabView`, since every
/// screen after Home belongs to a single case-preparation workflow, not a
/// set of independent top-level destinations.
enum AppRoute: Hashable {
    case newCase
    case interview(caseId: String, initialCase: MMCase?)
    case summary(caseId: String, initialCase: MMCase?)

    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case (.newCase, .newCase):
            return true
        case let (.interview(lhsId, _), .interview(rhsId, _)):
            return lhsId == rhsId
        case let (.summary(lhsId, _), .summary(rhsId, _)):
            return lhsId == rhsId
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .newCase:
            hasher.combine(0)
        case .interview(let caseId, _):
            hasher.combine(1)
            hasher.combine(caseId)
        case .summary(let caseId, _):
            hasher.combine(2)
            hasher.combine(caseId)
        }
    }
}
