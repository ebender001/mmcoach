package dev.benderapps.mmcoach.models

/** Display-facing view of the signed-in Parse User. Mirrors iOS `Models/AuthenticationState.swift`. */
data class AuthenticatedUser(
    val id: String,
    val email: String?,
    val isEmailVerified: Boolean,
    val signInMethod: SignInMethod,
) {
    enum class SignInMethod { EMAIL, GOOGLE }
}

/** Typed auth state driving the app root (see RootView / iOS `AuthenticationState`). */
sealed interface AuthenticationState {
    /** The app hasn't yet checked whether a persisted session exists. */
    data object CheckingSession : AuthenticationState

    /** Signing out or deleting the account is in progress. */
    data object EndingSession : AuthenticationState

    data object SignedOut : AuthenticationState

    data class SignedIn(val user: AuthenticatedUser) : AuthenticationState
}

/**
 * Stand-in signed-in user for the RootScreen shell until the real
 * Parse-backed AuthenticationViewModel is ported from iOS.
 */
val AuthenticatedUserPlaceholder = AuthenticatedUser(
    id = "placeholder",
    email = null,
    isEmailVerified = false,
    signInMethod = AuthenticatedUser.SignInMethod.EMAIL,
)
