//
//  BackendService.swift
//  MMCoach
//
//  The single interface between MMCoach and the Back4App Cloud Functions.
//  This is the ONLY file that talks to Parse-Swift. View models never call
//  Parse Cloud Functions directly, and no AI/clinical-completeness/
//  discussion-topic/reference logic lives here or anywhere on the client --
//  all of that is the backend's responsibility.
//
//  Flow: View -> ViewModel -> BackendService -> Back4App Cloud Function.
//

import Foundation
import ParseSwift

/// User-facing errors surfaced by `BackendService`. Raw Parse/OpenAI/server
/// error text is never shown to the trainee -- only these concise messages.
enum BackendError: LocalizedError, Equatable {
    case validation(String)
    case notFound
    case invalidState(String)
    /// The caller's Parse session is missing/expired/revoked -- every
    /// `mm*` Cloud Function requires one (see backend `requireUser`).
    /// `BackendService.run(_:)` also broadcasts `.sessionExpired` via
    /// `NotificationCenter` when this is thrown, which is what lets
    /// `AuthenticationViewModel` force a clean sign-out/re-auth instead of
    /// the app being stuck retrying calls a dead session can never pass.
    case sessionExpired
    case server
    case network
    case decoding

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .notFound:
            return "This case is no longer available."
        case .invalidState(let message):
            return message
        case .sessionExpired:
            return "Your session expired. Please sign in again."
        case .server:
            return "Something went wrong preparing your case. Please try again."
        case .network:
            return "M & M Coach couldn't reach the server. Check your connection and try again."
        case .decoding:
            return "M & M Coach couldn't read the server's response. Please try again."
        }
    }

    fileprivate init(parseError: ParseError) {
        switch parseError.code {
        case .validationFailed:
            self = .validation(parseError.message)
        case .objectNotFound:
            self = .notFound
        case .operationForbidden:
            self = .invalidState(parseError.message)
        case .invalidSessionToken:
            self = .sessionExpired
        case .connectionFailed, .timeout:
            self = .network
        default:
            self = .server
        }
    }
}

extension Notification.Name {
    /// Posted by `BackendService` whenever a Cloud Function call fails
    /// because the local session is no longer valid server-side.
    /// `AuthenticationViewModel` is the sole subscriber -- it forces a
    /// local sign-out and returns to the Welcome screen so the trainee
    /// re-authenticates instead of hitting the same dead-session error
    /// repeatedly on every subsequent case action.
    static let mmSessionExpired = Notification.Name("MMCoach.sessionExpired")
}

enum BackendService {
    static func createCase(narrative: String) async throws -> MMCase {
        try await run(CreateCaseFunction(narrative: narrative))
    }

    static func answerQuestion(caseId: String, questionId: String, answer: String) async throws -> MMCase {
        try await run(AnswerQuestionFunction(caseId: caseId, questionId: questionId, answer: answer))
    }

    static func finalizeCase(caseId: String) async throws -> MMCase {
        try await run(FinalizeCaseFunction(caseId: caseId))
    }

    static func getCase(caseId: String) async throws -> MMCase {
        try await run(GetCaseFunction(caseId: caseId))
    }

    /// Number of cases the signed-in user owns, regardless of status --
    /// the backend-sourced truth behind the paywall's first-case-free
    /// decision. Never derive this from `RecentCasesStore` (a local,
    /// per-device cache) or any other on-device count.
    static func getCaseCount() async throws -> Int {
        try await run(GetCaseCountFunction()).caseCount
    }

    /// Overwrites the polished narrative on an already-finalized case.
    /// Only valid once the case is `completed` -- the backend rejects it
    /// otherwise via `BackendError.invalidState`.
    static func updatePolishedNarrative(caseId: String, polishedNarrative: String) async throws -> MMCase {
        try await run(UpdatePolishedNarrativeFunction(caseId: caseId, polishedNarrative: polishedNarrative))
    }

    /// Live PubMed lookup for one reference topic -- not persisted to the
    /// case; the trainee reviews and picks their own sources rather than
    /// the app silently attaching one. `searchIntent` and `caseId` are
    /// both optional but should be passed whenever known: the backend
    /// uses `searchIntent` to craft a more targeted PubMed query, and
    /// `caseId` to verify ownership and roll this call's AI cost into
    /// that case's running total. Returns up to 5 results ordered by
    /// PubMed's own relevance ranking, or an empty array if nothing matched.
    static func findReferences(topic: String, searchIntent: String? = nil, caseId: String? = nil) async throws -> [PubMedReference] {
        try await run(FindReferencesFunction(topic: topic, searchIntent: searchIntent, caseId: caseId)).results
    }

    /// Corrects one freshly-dictated narrative segment. `priorNarrative` is
    /// passed only as context for disambiguation -- the backend does not
    /// re-edit it, and only `correctedSegment` should be appended locally.
    static func correctDictation(priorNarrative: String, newSegment: String) async throws -> CorrectedDictationSegment {
        try await run(CorrectDictationFunction(priorNarrative: priorNarrative, newSegment: newSegment))
    }

    private static func run<Function: ParseCloudable>(_ function: Function) async throws -> Function.ReturnType {
        do {
            return try await function.runFunction()
        } catch let error as ParseError {
            let mapped = BackendError(parseError: error)
            if mapped == .sessionExpired {
                NotificationCenter.default.post(name: .mmSessionExpired, object: nil)
            }
            throw mapped
        } catch is DecodingError {
            throw BackendError.decoding
        } catch {
            throw BackendError.network
        }
    }
}

// MARK: - Cloud Function request definitions
//
// Each Back4App Cloud Function gets one small ParseCloudable request type.
// Any stored property besides `functionJobName` is sent as a parameter.

private struct CreateCaseFunction: ParseCloudable {
    typealias ReturnType = MMCase
    var functionJobName = "mmCreateCase"
    var narrative: String
}

private struct AnswerQuestionFunction: ParseCloudable {
    typealias ReturnType = MMCase
    var functionJobName = "mmAnswerQuestion"
    var caseId: String
    var questionId: String
    var answer: String
}

private struct FinalizeCaseFunction: ParseCloudable {
    typealias ReturnType = MMCase
    var functionJobName = "mmFinalizeCase"
    var caseId: String
}

private struct GetCaseFunction: ParseCloudable {
    typealias ReturnType = MMCase
    var functionJobName = "mmGetCase"
    var caseId: String
}

private struct CaseCountResponse: Decodable {
    let caseCount: Int
}

private struct GetCaseCountFunction: ParseCloudable {
    typealias ReturnType = CaseCountResponse
    var functionJobName = "mmGetCaseCount"
}

private struct UpdatePolishedNarrativeFunction: ParseCloudable {
    typealias ReturnType = MMCase
    var functionJobName = "mmUpdatePolishedNarrative"
    var caseId: String
    var polishedNarrative: String
}

private struct FindReferencesFunction: ParseCloudable {
    typealias ReturnType = PubMedReferenceSearch
    var functionJobName = "mmFindReferences"
    var topic: String
    var searchIntent: String?
    var caseId: String?
}

private struct CorrectDictationFunction: ParseCloudable {
    typealias ReturnType = CorrectedDictationSegment
    var functionJobName = "mmCorrectDictation"
    var priorNarrative: String
    var newSegment: String
}
