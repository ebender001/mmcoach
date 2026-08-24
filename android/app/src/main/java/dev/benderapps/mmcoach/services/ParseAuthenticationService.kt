package dev.benderapps.mmcoach.services

import com.parse.ParseException
import com.parse.ParseUser
import dev.benderapps.mmcoach.models.AuthenticatedUser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The only class that calls Parse Android SDK authentication APIs.
 * Everything else (view models, screens) goes through the
 * [AuthenticationService] interface. Mirrors iOS `ParseAuthenticationService`.
 *
 * Flow: Screen -> AuthenticationViewModel -> AuthenticationService -> Parse.
 *
 * The Parse Android SDK's `ParseUser` auth calls (`signUp`, `logIn`,
 * `requestPasswordReset`, `logOut`) are blocking rather than
 * coroutine-native, so each is run on [Dispatchers.IO].
 */
class ParseAuthenticationService : AuthenticationService {
    override fun currentUser(): AuthenticatedUser? =
        ParseUser.getCurrentUser()?.toAuthenticatedUser()

    override suspend fun signUp(email: String, password: String): AuthenticatedUser =
        withContext(Dispatchers.IO) {
            try {
                val newUser = ParseUser()
                newUser.username = email
                newUser.email = email
                newUser.setPassword(password)
                newUser.signUp()
                newUser.toAuthenticatedUser()
            } catch (error: ParseException) {
                throw error.toServiceError()
            }
        }

    override suspend fun signIn(email: String, password: String): AuthenticatedUser =
        withContext(Dispatchers.IO) {
            try {
                ParseUser.logIn(email, password).toAuthenticatedUser()
            } catch (error: ParseException) {
                throw error.toServiceError()
            }
        }

    override suspend fun sendPasswordReset(email: String) {
        withContext(Dispatchers.IO) {
            try {
                ParseUser.requestPasswordReset(email)
            } catch (error: ParseException) {
                // Parse Server's password-reset endpoint intentionally does
                // not reveal whether the email is registered -- any
                // non-network failure here is treated the same as success
                // by the caller (see AuthenticationViewModel).
                if (error.isNetworkFailure()) throw AuthenticationServiceError.Network
            }
        }
    }

    override suspend fun signOut() {
        withContext(Dispatchers.IO) {
            try {
                ParseUser.logOut()
            } catch (error: ParseException) {
                throw error.toServiceError()
            }
        }
    }

    private fun ParseException.isNetworkFailure(): Boolean =
        code == ParseException.CONNECTION_FAILED || code == ParseException.TIMEOUT

    private fun ParseException.toServiceError(): AuthenticationServiceError = when (code) {
        ParseException.USERNAME_TAKEN, ParseException.EMAIL_TAKEN -> AuthenticationServiceError.EmailAlreadyInUse
        // Parse Server returns this same code for "wrong username/password"
        // as for "object not found" -- in a login context it always means
        // invalid credentials.
        ParseException.OBJECT_NOT_FOUND -> AuthenticationServiceError.InvalidCredentials
        ParseException.VALIDATION_ERROR ->
            AuthenticationServiceError.Validation(message ?: "Please check your information and try again.")
        ParseException.CONNECTION_FAILED, ParseException.TIMEOUT -> AuthenticationServiceError.Network
        else -> AuthenticationServiceError.Server
    }

    private fun ParseUser.toAuthenticatedUser() = AuthenticatedUser(
        id = objectId ?: "",
        email = email,
        isEmailVerified = getBoolean("emailVerified"),
    )
}
