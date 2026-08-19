//
//  AppleSignInService.swift
//  MMCoach
//
//  Turns the raw `ASAuthorization` result from SwiftUI's native
//  `SignInWithAppleButton` (which owns presenting the system UI itself)
//  into a typed, Parse-agnostic credential -- or a typed error, with
//  cancellation kept distinct from an actual failure. This is the only
//  file that imports AuthenticationServices; `AuthenticationViewModel`
//  hands the resulting credential to `AuthenticationService`, which is
//  the only thing that talks to Parse.
//

import AuthenticationServices
import Foundation

/// What MMCoach needs from a Sign in with Apple authorization. `fullName`
/// and `email` are only ever present on the *first* authorization for a
/// given app -- callers must not assume either is populated on repeat
/// sign-ins, only that `userIdentifier` is stable across all of them.
struct AppleSignInCredential {
    let userIdentifier: String
    let identityToken: Data
    let fullName: PersonNameComponents?
    let email: String?
}

enum AppleSignInError: Error, Equatable {
    /// The person dismissed the Apple sheet themselves -- callers should
    /// handle this silently, not show an error.
    case cancelled
    /// The authorization succeeded but didn't contain what MMCoach needs
    /// (wrong credential type, or no identity token) -- this shouldn't
    /// happen in practice, but is a real failure if it does.
    case invalidResponse
    /// A genuine failure (network, Apple-side issue, ASAuthorizationError
    /// other than cancellation, etc.) -- callers should show an error.
    case failed
}

protocol AppleSignInCredentialExtracting {
    func credential(from result: Result<ASAuthorization, Error>) throws -> AppleSignInCredential
}

struct AppleSignInService: AppleSignInCredentialExtracting {
    func credential(from result: Result<ASAuthorization, Error>) throws -> AppleSignInCredential {
        switch result {
        case .failure(let error):
            throw mapError(error)
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken else {
                throw AppleSignInError.invalidResponse
            }
            return AppleSignInCredential(
                userIdentifier: appleIDCredential.user,
                identityToken: identityToken,
                fullName: appleIDCredential.fullName,
                email: appleIDCredential.email
            )
        }
    }

    private func mapError(_ error: Error) -> AppleSignInError {
        guard let authError = error as? ASAuthorizationError else {
            return .failed
        }
        switch authError.code {
        case .canceled:
            return .cancelled
        default:
            return .failed
        }
    }
}
