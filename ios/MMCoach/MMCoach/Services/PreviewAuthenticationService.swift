//
//  PreviewAuthenticationService.swift
//  MMCoach
//
//  Mock `AuthenticationService`/`AppleSignInCredentialExtracting`
//  implementations, kept in Services/ alongside the protocols they
//  implement. Used by SwiftUI previews (see WelcomeView,
//  EmailAuthenticationView, PasswordResetView) and available the same way
//  to a future unit test target -- the protocol boundary these mock is
//  exactly what makes AuthenticationViewModel testable without Parse or
//  AuthenticationServices.
//

#if DEBUG
import AuthenticationServices
import Foundation

struct PreviewAuthenticationService: AuthenticationService {
    var currentUserResult: AuthenticatedUser?
    var signInResult: Result<AuthenticatedUser, Error> = .success(.preview)
    var signUpResult: Result<AuthenticatedUser, Error> = .success(.preview)
    var signInWithAppleResult: Result<AuthenticatedUser, Error> = .success(.preview)
    var passwordResetError: Error?
    var signOutError: Error?
    var deleteAccountError: Error?

    func currentUser() -> AuthenticatedUser? { currentUserResult }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        try signInResult.get()
    }

    func signUp(email: String, password: String) async throws -> AuthenticatedUser {
        try signUpResult.get()
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthenticatedUser {
        try signInWithAppleResult.get()
    }

    func sendPasswordReset(email: String) async throws {
        if let passwordResetError { throw passwordResetError }
    }

    func signOut() async throws {
        if let signOutError { throw signOutError }
    }

    func deleteAccount() async throws {
        if let deleteAccountError { throw deleteAccountError }
    }
}

struct PreviewAppleSignInService: AppleSignInCredentialExtracting {
    var result: Result<AppleSignInCredential, Error> = .failure(AppleSignInError.cancelled)

    func credential(from result: Result<ASAuthorization, Error>) throws -> AppleSignInCredential {
        try self.result.get()
    }
}

extension AuthenticatedUser {
    static let preview = AuthenticatedUser(id: "preview-user",
                                            email: "trainee@example.edu",
                                            isEmailVerified: true,
                                            signInMethod: .email)

    static let previewApple = AuthenticatedUser(id: "preview-apple-user",
                                                 email: nil,
                                                 isEmailVerified: false,
                                                 signInMethod: .apple)
}
#endif
