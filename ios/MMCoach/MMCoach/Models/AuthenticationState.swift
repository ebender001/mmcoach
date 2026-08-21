//
//  AuthenticationState.swift
//  MMCoach
//
//  Typed auth state driving the app root (see RootView): which of the
//  Welcome screen or the MM Coach home screen is shown, and the loading
//  state while the persisted Parse session is being checked at launch.
//

import Foundation

/// Display-facing view of the signed-in Parse User. Kept separate from
/// the `User`/`ParseUser` type so views and view models never need to
/// import ParseSwift or touch Parse types directly (see
/// `Services/AuthenticationService.swift`).
struct AuthenticatedUser: Equatable {
    enum SignInMethod: Equatable {
        case email
        case apple
    }

    let id: String
    let email: String?
    let isEmailVerified: Bool
    let signInMethod: SignInMethod
}

enum AuthenticationState: Equatable {
    /// The app hasn't yet checked whether a persisted session exists.
    case checkingSession
    /// Signing out or deleting the account is in progress -- shown
    /// between `.signedIn` and `.signedOut` so that transition has a
    /// visible in-between state (a spinner) rather than either freezing
    /// on Home during the network call or cutting straight to Welcome.
    /// See `AuthenticationViewModel.signOut()`/`deleteAccount()`.
    case endingSession
    case signedOut
    case signedIn(AuthenticatedUser)
}
