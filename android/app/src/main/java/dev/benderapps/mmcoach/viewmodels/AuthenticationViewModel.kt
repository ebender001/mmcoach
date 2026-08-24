package dev.benderapps.mmcoach.viewmodels

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.benderapps.mmcoach.models.AuthenticationState
import dev.benderapps.mmcoach.services.AuthenticationService
import dev.benderapps.mmcoach.services.AuthenticationServiceError
import dev.benderapps.mmcoach.services.ParseAuthenticationService
import kotlinx.coroutines.launch

enum class EmailAuthMode { SIGN_IN, CREATE_ACCOUNT }

/**
 * Drives every authentication screen (Welcome, EmailAuthScreen,
 * PasswordResetScreen) and the app-root decision between them and Home
 * (see RootScreen). Screens only ever call this -- never
 * AuthenticationService/Parse directly. Mirrors iOS `AuthenticationViewModel`.
 */
class AuthenticationViewModel(
    private val authService: AuthenticationService = ParseAuthenticationService(),
) : ViewModel() {
    var state by mutableStateOf<AuthenticationState>(AuthenticationState.CheckingSession)
        private set

    // Email sign-in / create-account form
    var emailMode by mutableStateOf(EmailAuthMode.SIGN_IN)
    var email by mutableStateOf("")
    var password by mutableStateOf("")
    var confirmPassword by mutableStateOf("")
    var isPasswordVisible by mutableStateOf(false)
    var isSubmittingEmailForm by mutableStateOf(false)
        private set
    var emailFieldError by mutableStateOf<String?>(null)
        private set
    var passwordFieldError by mutableStateOf<String?>(null)
        private set
    var confirmPasswordFieldError by mutableStateOf<String?>(null)
        private set
    var formErrorMessage by mutableStateOf<String?>(null)
        private set

    // Password reset
    var resetEmail by mutableStateOf("")
    var isSendingResetLink by mutableStateOf(false)
        private set
    var resetEmailFieldError by mutableStateOf<String?>(null)
        private set
    var resetErrorMessage by mutableStateOf<String?>(null)
        private set
    var resetConfirmationMessage by mutableStateOf<String?>(null)
        private set

    /** Checks for an already-persisted session at launch (see RootScreen). */
    fun refreshSession() {
        state = authService.currentUser()
            ?.let(AuthenticationState::SignedIn)
            ?: AuthenticationState.SignedOut
    }

    /**
     * Clears form-specific errors and the password fields (but not the
     * email) -- call when switching between Sign In and Create Account, or
     * when presenting the form fresh.
     */
    fun resetEmailForm() {
        password = ""
        confirmPassword = ""
        isPasswordVisible = false
        emailFieldError = null
        passwordFieldError = null
        confirmPasswordFieldError = null
        formErrorMessage = null
    }

    fun submitEmailForm() {
        if (isSubmittingEmailForm) return
        formErrorMessage = null
        if (!validateEmailForm()) return

        viewModelScope.launch {
            isSubmittingEmailForm = true
            try {
                val normalizedEmail = email.trim().lowercase()
                val user = when (emailMode) {
                    EmailAuthMode.SIGN_IN -> authService.signIn(normalizedEmail, password)
                    EmailAuthMode.CREATE_ACCOUNT -> authService.signUp(normalizedEmail, password)
                }
                state = AuthenticationState.SignedIn(user)
            } catch (error: AuthenticationServiceError) {
                formErrorMessage = error.userMessage
            } catch (error: Exception) {
                formErrorMessage = AuthenticationServiceError.Network.userMessage
            } finally {
                isSubmittingEmailForm = false
            }
        }
    }

    private fun validateEmailForm(): Boolean {
        emailFieldError = null
        passwordFieldError = null
        confirmPasswordFieldError = null

        var isValid = true
        if (!isValidEmail(email.trim())) {
            emailFieldError = "Enter a valid email address."
            isValid = false
        }
        if (password.length < MINIMUM_PASSWORD_LENGTH) {
            passwordFieldError = "Use at least $MINIMUM_PASSWORD_LENGTH characters."
            isValid = false
        }
        if (emailMode == EmailAuthMode.CREATE_ACCOUNT && password.isNotEmpty() && password != confirmPassword) {
            confirmPasswordFieldError = "Passwords don't match."
            isValid = false
        }
        return isValid
    }

    fun resetPasswordResetForm() {
        resetEmailFieldError = null
        resetErrorMessage = null
        resetConfirmationMessage = null
    }

    fun sendPasswordReset() {
        if (isSendingResetLink) return
        resetErrorMessage = null
        resetConfirmationMessage = null
        resetEmailFieldError = null

        val normalizedEmail = resetEmail.trim().lowercase()
        if (!isValidEmail(normalizedEmail)) {
            resetEmailFieldError = "Enter a valid email address."
            return
        }

        viewModelScope.launch {
            isSendingResetLink = true
            try {
                authService.sendPasswordReset(normalizedEmail)
                resetConfirmationMessage = "We sent password-reset instructions if an account exists for that email."
            } catch (error: AuthenticationServiceError) {
                resetErrorMessage = error.userMessage
            } catch (error: Exception) {
                resetErrorMessage = AuthenticationServiceError.Network.userMessage
            } finally {
                isSendingResetLink = false
            }
        }
    }

    /**
     * Clears the local Parse session and returns to the Welcome screen.
     * Moves to [AuthenticationState.EndingSession] *before* the network
     * call since sign-out can't meaningfully fail from the UI's point of
     * view -- there's nothing to stay on Home for.
     */
    fun signOut() {
        viewModelScope.launch {
            state = AuthenticationState.EndingSession
            try {
                authService.signOut()
            } catch (_: Exception) {
                // Best-effort -- the local session is cleared either way.
            }
            state = AuthenticationState.SignedOut
        }
    }

    private companion object {
        const val MINIMUM_PASSWORD_LENGTH = 8
        val EMAIL_PATTERN = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

        fun isValidEmail(value: String): Boolean =
            value.isNotEmpty() && EMAIL_PATTERN.matches(value)
    }
}
