//
//  AuthenticationService.swift
//  MMCoach
//
//  The single interface between MMCoach and account authentication. Views
//  and view models never call Parse or AuthenticationServices APIs
//  directly -- see `AuthenticationViewModel`, which is the only caller of
//  this protocol, and `ParseAuthenticationService`, the only concrete
//  implementation. Protocol-based so it can be mocked in tests/previews.
//
//  Flow: View -> AuthenticationViewModel -> AuthenticationService -> Parse.
//

import Foundation

/// User-facing errors surfaced by `AuthenticationService`. Raw Parse error
/// text is never shown to the trainee -- only these concise messages.
enum AuthenticationServiceError: LocalizedError, Equatable {
    case invalidCredentials
    case emailAlreadyInUse
    /// A server-side validation rule was rejected (e.g. a Back4App
    /// password-policy requirement) -- the message is server-authored but
    /// already user-safe, unlike other Parse error text.
    case validation(String)
    case network
    case server

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "That email and password don't match. Please try again."
        case .emailAlreadyInUse:
            return "An account already exists for that email."
        case .validation(let message):
            return message
        case .network:
            return "MMCoach couldn't reach the server. Check your connection and try again."
        case .server:
            return "Something went wrong. Please try again."
        }
    }
}

protocol AuthenticationService {
    /// The signed-in user, if a session is already persisted (e.g. from a
    /// previous launch). Synchronous: the Parse SDK caches this in memory
    /// (backed by the Keychain) rather than making a network call.
    func currentUser() -> AuthenticatedUser?

    func signUp(email: String, password: String) async throws -> AuthenticatedUser
    func signIn(email: String, password: String) async throws -> AuthenticatedUser
    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthenticatedUser

    /// Always succeeds from the caller's point of view (matches Parse
    /// Server's own enumeration-safe behavior) unless the request never
    /// reached the server -- see `ParseAuthenticationService`.
    func sendPasswordReset(email: String) async throws

    func signOut() async throws
}
