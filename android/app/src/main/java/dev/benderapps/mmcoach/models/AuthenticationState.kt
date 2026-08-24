package dev.benderapps.mmcoach.models

/**
 * Display-facing view of the signed-in Parse User. Mirrors iOS
 * `Models/AuthenticationState.swift`, minus `signInMethod` -- email is the
 * only sign-in method the Android client supports so far.
 */
data class AuthenticatedUser(
    val id: String,
    val email: String?,
    val isEmailVerified: Boolean,
)

/** Typed auth state driving the app root (see RootScreen / iOS `AuthenticationState`). */
sealed interface AuthenticationState {
    /** The app hasn't yet checked whether a persisted session exists. */
    data object CheckingSession : AuthenticationState

    /** Signing out is in progress. */
    data object EndingSession : AuthenticationState

    data object SignedOut : AuthenticationState

    data class SignedIn(val user: AuthenticatedUser) : AuthenticationState
}
