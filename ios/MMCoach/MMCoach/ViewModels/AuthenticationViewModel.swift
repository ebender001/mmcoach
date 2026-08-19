//
//  AuthenticationViewModel.swift
//  MMCoach
//
//  Drives every authentication screen (Welcome, EmailAuthenticationView,
//  PasswordResetView) and the app-root decision between them and Home
//  (see RootView). Views only ever call this -- never
//  AuthenticationService/AppleSignInService/Parse/AuthenticationServices
//  directly.
//

import AuthenticationServices
import Combine
import Foundation

enum EmailAuthMode: Equatable {
    case signIn
    case createAccount
}

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published private(set) var state: AuthenticationState = .checkingSession

    // Sign in with Apple
    @Published private(set) var isAppleSignInInProgress = false
    @Published var appleSignInErrorMessage: String?

    // Email sign-in/create-account sheet
    @Published var emailMode: EmailAuthMode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isPasswordVisible = false
    @Published private(set) var isSubmittingEmailForm = false
    @Published private(set) var emailFieldError: String?
    @Published private(set) var passwordFieldError: String?
    @Published private(set) var confirmPasswordFieldError: String?
    @Published var formErrorMessage: String?

    // Password reset
    @Published var resetEmail = ""
    @Published private(set) var isSendingResetLink = false
    @Published private(set) var resetEmailFieldError: String?
    @Published var resetErrorMessage: String?
    @Published private(set) var resetConfirmationMessage: String?

    private static let minimumPasswordLength = 8

    private let authService: AuthenticationService
    private let appleSignIn: AppleSignInCredentialExtracting

    init(authService: AuthenticationService = ParseAuthenticationService(),
         appleSignIn: AppleSignInCredentialExtracting = AppleSignInService()) {
        self.authService = authService
        self.appleSignIn = appleSignIn
    }

    /// Checks for an already-persisted session at launch. Fast and
    /// synchronous under the hood (Parse caches this from the Keychain),
    /// but modeled as async so `RootView` can show a brief loading state
    /// rather than assume it's instantaneous.
    func refreshSession() async {
        state = authService.currentUser().map(AuthenticationState.signedIn) ?? .signedOut
    }

    // MARK: - Sign in with Apple

    /// Called from `SignInWithAppleButton`'s `onCompletion`. The button
    /// itself (SwiftUI/AuthenticationServices) already presented the
    /// system UI and produced this result -- this only interprets it.
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        appleSignInErrorMessage = nil
        do {
            let credential = try appleSignIn.credential(from: result)
            isAppleSignInInProgress = true
            defer { isAppleSignInInProgress = false }
            let user = try await authService.signInWithApple(credential)
            state = .signedIn(user)
        } catch AppleSignInError.cancelled {
            // The person dismissed the Apple sheet -- not an error.
        } catch let error as AuthenticationServiceError {
            appleSignInErrorMessage = error.errorDescription
        } catch {
            appleSignInErrorMessage = "Sign in with Apple didn't complete. Please try again."
        }
    }

    // MARK: - Email / password

    /// Clears form-specific errors and the password fields (but not the
    /// email) -- call when switching between Sign In and Create Account,
    /// or when presenting the sheet fresh.
    func resetEmailForm() {
        password = ""
        confirmPassword = ""
        isPasswordVisible = false
        emailFieldError = nil
        passwordFieldError = nil
        confirmPasswordFieldError = nil
        formErrorMessage = nil
    }

    func submitEmailForm() async {
        guard !isSubmittingEmailForm else { return }
        formErrorMessage = nil
        guard validateEmailForm() else { return }

        isSubmittingEmailForm = true
        defer { isSubmittingEmailForm = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let user: AuthenticatedUser
            switch emailMode {
            case .signIn:
                user = try await authService.signIn(email: normalizedEmail, password: password)
            case .createAccount:
                user = try await authService.signUp(email: normalizedEmail, password: password)
            }
            state = .signedIn(user)
        } catch let error as AuthenticationServiceError {
            formErrorMessage = error.errorDescription
        } catch {
            formErrorMessage = AuthenticationServiceError.network.errorDescription
        }
    }

    private func validateEmailForm() -> Bool {
        emailFieldError = nil
        passwordFieldError = nil
        confirmPasswordFieldError = nil

        var isValid = true
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.isValidEmail(normalizedEmail) {
            emailFieldError = "Enter a valid email address."
            isValid = false
        }
        if password.count < Self.minimumPasswordLength {
            passwordFieldError = "Use at least \(Self.minimumPasswordLength) characters."
            isValid = false
        }
        if emailMode == .createAccount, !password.isEmpty, password != confirmPassword {
            confirmPasswordFieldError = "Passwords don't match."
            isValid = false
        }
        return isValid
    }

    // MARK: - Password reset

    func resetPasswordResetForm() {
        resetEmailFieldError = nil
        resetErrorMessage = nil
        resetConfirmationMessage = nil
    }

    func sendPasswordReset() async {
        guard !isSendingResetLink else { return }
        resetErrorMessage = nil
        resetConfirmationMessage = nil
        resetEmailFieldError = nil

        let normalizedEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(normalizedEmail) else {
            resetEmailFieldError = "Enter a valid email address."
            return
        }

        isSendingResetLink = true
        defer { isSendingResetLink = false }

        do {
            try await authService.sendPasswordReset(email: normalizedEmail)
            resetConfirmationMessage = "We sent password-reset instructions if an account exists for that email."
        } catch let error as AuthenticationServiceError {
            resetErrorMessage = error.errorDescription
        } catch {
            resetErrorMessage = AuthenticationServiceError.network.errorDescription
        }
    }

    // MARK: - Sign out

    /// Clears the local Parse session (see `ParseAuthenticationService`)
    /// and returns to the Welcome screen. Never touches case data --
    /// `RecentCasesStore` and any in-flight case on the backend are
    /// untouched.
    func signOut() async {
        try? await authService.signOut()
        state = .signedOut
    }

    private static func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
