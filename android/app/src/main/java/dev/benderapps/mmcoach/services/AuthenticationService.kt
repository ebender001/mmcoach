package dev.benderapps.mmcoach.services

import dev.benderapps.mmcoach.models.AuthenticatedUser

/**
 * User-facing errors surfaced by [AuthenticationService]. Raw Parse error
 * text is never shown to the trainee -- only these concise messages.
 * Mirrors iOS `AuthenticationServiceError`.
 */
sealed class AuthenticationServiceError(val userMessage: String) : Exception(userMessage) {
    data object InvalidCredentials :
        AuthenticationServiceError("That email and password don't match. Please try again.")

    data object EmailAlreadyInUse :
        AuthenticationServiceError("An account already exists for that email.")

    /** A server-side validation rule was rejected -- the message is server-authored but already user-safe. */
    class Validation(message: String) : AuthenticationServiceError(message)

    data object Network :
        AuthenticationServiceError("MM Coach couldn't reach the server. Check your connection and try again.")

    data object Server :
        AuthenticationServiceError("Something went wrong. Please try again.")
}

/**
 * The single interface between MMCoach and account authentication.
 * ViewModels never call the Parse SDK directly -- see
 * [AuthenticationViewModel][dev.benderapps.mmcoach.viewmodels.AuthenticationViewModel],
 * the only caller of this interface, and [ParseAuthenticationService], the
 * only implementation. Mirrors iOS `AuthenticationService`.
 */
interface AuthenticationService {
    /** The signed-in user, if a session is already persisted from a previous launch. */
    fun currentUser(): AuthenticatedUser?

    suspend fun signUp(email: String, password: String): AuthenticatedUser
    suspend fun signIn(email: String, password: String): AuthenticatedUser

    /**
     * Always succeeds from the caller's point of view (matches Parse
     * Server's own enumeration-safe behavior) unless the request never
     * reached the server.
     */
    suspend fun sendPasswordReset(email: String)

    suspend fun signOut()
}
