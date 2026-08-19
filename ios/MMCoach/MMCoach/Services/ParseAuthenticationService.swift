//
//  ParseAuthenticationService.swift
//  MMCoach
//
//  The only file that calls ParseUser/Parse-Swift authentication APIs.
//  Everything else (views, view models) goes through the
//  `AuthenticationService` protocol -- see that file for the flow.
//

import Foundation
import ParseSwift

struct ParseAuthenticationService: AuthenticationService {
    func currentUser() -> AuthenticatedUser? {
        User.current.map(AuthenticatedUser.init(parseUser:))
    }

    func signUp(email: String, password: String) async throws -> AuthenticatedUser {
        var newUser = User()
        newUser.username = email
        newUser.email = email
        newUser.password = password
        do {
            let signedUp = try await newUser.signup()
            return AuthenticatedUser(parseUser: signedUp)
        } catch let error as ParseError {
            throw map(error)
        } catch {
            throw AuthenticationServiceError.network
        }
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        do {
            let loggedIn = try await User.login(username: email, password: password)
            return AuthenticatedUser(parseUser: loggedIn)
        } catch let error as ParseError {
            throw map(error)
        } catch {
            throw AuthenticationServiceError.network
        }
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthenticatedUser {
        do {
            var loggedIn = try await User.apple.login(user: credential.userIdentifier,
                                                        identityToken: credential.identityToken)

            var needsSave = false

            // Parse Server already links repeat sign-ins by the identity
            // baked into `authData` -- this field is an explicit, directly
            // queryable record of the same id, not what the linking
            // itself depends on.
            if loggedIn.appleUserIdentifier != credential.userIdentifier {
                loggedIn.appleUserIdentifier = credential.userIdentifier
                needsSave = true
            }

            // Apple only includes the email (and name) on the *first*
            // authorization for this app/Apple ID pair -- it won't be
            // resent on any later sign-in, so persist it the one time
            // it's actually present rather than leaving it unset.
            if loggedIn.email == nil, let email = credential.email {
                loggedIn.email = email
                needsSave = true
            }

            if needsSave {
                loggedIn = try await loggedIn.save()
            }

            return AuthenticatedUser(parseUser: loggedIn)
        } catch let error as ParseError {
            throw map(error)
        } catch {
            throw AuthenticationServiceError.network
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await User.passwordReset(email: email)
        } catch let error as ParseError where isNetworkFailure(error) {
            throw AuthenticationServiceError.network
        } catch {
            // Parse Server's password-reset endpoint intentionally does
            // not reveal whether the email is registered (it returns
            // success either way in most configurations, and even where
            // it doesn't, MMCoach must not surface that distinction) --
            // any non-network failure here is treated the same as success
            // by the caller. See `AuthenticationViewModel`.
        }
    }

    func signOut() async throws {
        do {
            try await User.logout()
        } catch let error as ParseError {
            throw map(error)
        } catch {
            throw AuthenticationServiceError.network
        }
    }

    private func isNetworkFailure(_ error: ParseError) -> Bool {
        error.code == .connectionFailed || error.code == .timeout
    }

    private func map(_ error: ParseError) -> AuthenticationServiceError {
        switch error.code {
        case .usernameTaken, .userEmailTaken:
            return .emailAlreadyInUse
        case .objectNotFound:
            // Parse Server returns this same code for "wrong
            // username/password" as for "object not found" -- in a
            // login context it always means invalid credentials.
            return .invalidCredentials
        case .validationFailed:
            return .validation(error.message)
        case .connectionFailed, .timeout:
            return .network
        default:
            return .server
        }
    }
}

private extension AuthenticatedUser {
    init(parseUser: User) {
        self.init(
            id: parseUser.objectId ?? "",
            email: parseUser.email,
            isEmailVerified: parseUser.emailVerified ?? false,
            signInMethod: (parseUser.appleUserIdentifier?.isEmpty == false) ? .apple : .email
        )
    }
}
