package dev.benderapps.mmcoach.ui.screens

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.benderapps.mmcoach.models.AuthenticationState
import dev.benderapps.mmcoach.viewmodels.AuthenticationViewModel

private enum class AuthFlowScreen { WELCOME, EMAIL, PASSWORD_RESET }

/**
 * App root: switches between the Welcome/authentication flow and the MM
 * Coach home screen based on auth state. Mirrors iOS `App/RootView.swift`.
 */
@Composable
fun RootScreen(authViewModel: AuthenticationViewModel = viewModel()) {
    LaunchedEffect(Unit) { authViewModel.refreshSession() }

    Surface(
        modifier = Modifier.safeDrawingPadding(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Crossfade(targetState = authViewModel.state, label = "authState") { state ->
            when (state) {
                is AuthenticationState.CheckingSession, is AuthenticationState.EndingSession -> LoadingScreen()
                is AuthenticationState.SignedOut -> AuthFlow(authViewModel)
                is AuthenticationState.SignedIn -> HomeScreen(
                    currentUser = state.user,
                    onSignOut = { authViewModel.signOut() },
                )
            }
        }
    }
}

@Composable
private fun AuthFlow(authViewModel: AuthenticationViewModel) {
    var screen by remember { mutableStateOf(AuthFlowScreen.WELCOME) }

    Crossfade(targetState = screen, label = "authFlowScreen") { current ->
        when (current) {
            AuthFlowScreen.WELCOME -> WelcomeScreen(
                onContinueWithEmail = {
                    authViewModel.resetEmailForm()
                    screen = AuthFlowScreen.EMAIL
                },
            )
            AuthFlowScreen.EMAIL -> EmailAuthScreen(
                viewModel = authViewModel,
                onDismiss = { screen = AuthFlowScreen.WELCOME },
                onForgotPassword = {
                    authViewModel.resetPasswordResetForm()
                    authViewModel.resetEmail = authViewModel.email
                    screen = AuthFlowScreen.PASSWORD_RESET
                },
            )
            AuthFlowScreen.PASSWORD_RESET -> PasswordResetScreen(
                viewModel = authViewModel,
                onDismiss = { screen = AuthFlowScreen.EMAIL },
            )
        }
    }
}

@Composable
private fun LoadingScreen() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
    }
}
