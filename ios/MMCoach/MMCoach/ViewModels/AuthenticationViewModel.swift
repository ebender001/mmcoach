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
    /// Set only when `state` moves to `.signedOut` because the backend
    /// rejected a call with an expired/invalid session (see
    /// `.mmSessionExpired` in BackendService) -- not on an explicit Sign
    /// Out from AccountView. Shown on WelcomeView so landing back there
    /// unexpectedly doesn't look like a bug.
    @Published private(set) var sessionExpiredMessage: String?

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
    private var sessionExpiryObservation: AnyCancellable?

    init(authService: AuthenticationService? = nil,
         appleSignIn: AppleSignInCredentialExtracting? = nil) {
        self.authService = authService ?? ParseAuthenticationService()
        self.appleSignIn = appleSignIn ?? AppleSignInService()
        sessionExpiryObservation = NotificationCenter.default
            .publisher(for: .mmSessionExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.handleSessionExpired() }
            }
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
        sessionExpiredMessage = nil
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
        sessionExpiredMessage = nil
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
        sessionExpiredMessage = nil
    }

    /// There is no way to silently obtain a new session without the
    /// person re-authenticating -- Parse never gives the client a stored
    /// password to replay, and Apple doesn't hand out a fresh identity
    /// token without its own UI. So this doesn't attempt a background
    /// login; it clears the dead local session (mirroring `signOut()`,
    /// including tolerating `authService.signOut()` itself failing, since
    /// the session it's trying to invalidate server-side is already the
    /// one that's invalid) and routes back to Welcome with an explanation,
    /// rather than leaving the trainee stuck retrying case actions that
    /// can never succeed with a dead session.
    private func handleSessionExpired() async {
        guard case .signedIn = state else { return }
        try? await authService.signOut()
        state = .signedOut
        sessionExpiredMessage = "Your session expired. Please sign in again."
    }

    private static func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
