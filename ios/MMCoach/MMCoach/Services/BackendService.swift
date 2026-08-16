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
        case .server:
            return "Something went wrong preparing your case. Please try again."
        case .network:
            return "MMCoach couldn't reach the server. Check your connection and try again."
        case .decoding:
            return "MMCoach couldn't read the server's response. Please try again."
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
        case .connectionFailed, .timeout:
            self = .network
        default:
            self = .server
        }
    }
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

    private static func run<Function: ParseCloudable>(_ function: Function) async throws -> Function.ReturnType {
        do {
            return try await function.runFunction()
        } catch let error as ParseError {
            throw BackendError(parseError: error)
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
