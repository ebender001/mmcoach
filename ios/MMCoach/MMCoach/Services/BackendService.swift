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

    /// Whether a free first case is available -- true only if this
    /// account owns zero cases AND this device (see
    /// `DeviceIdentifierService`) has never redeemed one before, even
    /// under a different/deleted account. Never derive this from
    /// `RecentCasesStore` (a local, per-device case cache) or any other
    /// on-device signal.
    static func checkFreeCaseEligibility(deviceId: String) async throws -> Bool {
        try await run(CheckFreeCaseEligibilityFunction(deviceId: deviceId)).eligible
    }

    /// Marks this device as having redeemed its free first case.
    /// Deliberately separate from the eligibility check above -- call
    /// this only at the moment the trainee actually taps "Continue with
    /// Your Free Case", not when merely checking whether to show that
    /// option, so a person who never uses the free case never burns it.
    /// The backend re-validates eligibility atomically and throws
    /// `BackendError.invalidState` if it's no longer available (e.g. a
    /// stale paywall).
    static func redeemFreeCase(deviceId: String) async throws {
        _ = try await run(RedeemFreeCaseFunction(deviceId: deviceId))
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

    /// Drafts a model answer to one of the case's own likely faculty
    /// questions -- a live, on-demand rehearsal aid; not persisted to the
    /// case, so it's recomputed each time it's requested (mirrors
    /// `findReferences`).
    static func answerFacultyQuestion(caseId: String, question: String) async throws -> String {
        try await run(AnswerFacultyQuestionFunction(caseId: caseId, question: question)).answer
    }

    /// Corrects one freshly-dictated narrative segment. `priorNarrative` is
    /// passed only as context for disambiguation -- the backend does not
    /// re-edit it, and only `correctedSegment` should be appended locally.
    static func correctDictation(priorNarrative: String, newSegment: String) async throws -> CorrectedDictationSegment {
        try await run(CorrectDictationFunction(priorNarrative: priorNarrative, newSegment: newSegment))
    }

    /// Permanently deletes the signed-in account and every case/AI-cost
    /// record it owns. Irreversible, and there is no confirmation step on
    /// the backend -- the caller (AccountView) is responsible for
    /// confirming with the person first.
    static func deleteAccount() async throws {
        _ = try await run(DeleteAccountFunction())
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

private struct FreeCaseEligibilityResponse: Decodable {
    let eligible: Bool
}

private struct CheckFreeCaseEligibilityFunction: ParseCloudable {
    typealias ReturnType = FreeCaseEligibilityResponse
    var functionJobName = "mmCheckFreeCaseEligibility"
    var deviceId: String
}

private struct RedeemFreeCaseResponse: Decodable {
    let redeemed: Bool
}

private struct RedeemFreeCaseFunction: ParseCloudable {
    typealias ReturnType = RedeemFreeCaseResponse
    var functionJobName = "mmRedeemFreeCase"
    var deviceId: String
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

private struct AnswerFacultyQuestionFunction: ParseCloudable {
    typealias ReturnType = FacultyQuestionAnswer
    var functionJobName = "mmAnswerFacultyQuestion"
    var caseId: String
    var question: String
}

private struct CorrectDictationFunction: ParseCloudable {
    typealias ReturnType = CorrectedDictationSegment
    var functionJobName = "mmCorrectDictation"
    var priorNarrative: String
    var newSegment: String
}

private struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}

private struct DeleteAccountFunction: ParseCloudable {
    typealias ReturnType = DeleteAccountResponse
    var functionJobName = "mmDeleteAccount"
}
