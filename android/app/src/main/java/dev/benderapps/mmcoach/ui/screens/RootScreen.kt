package dev.benderapps.mmcoach.ui.screens

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.benderapps.mmcoach.models.AuthenticatedUserPlaceholder
import dev.benderapps.mmcoach.models.AuthenticationState

/**
 * App root: switches between the Welcome/authentication flow and the MM
 * Coach home screen based on auth state. Mirrors iOS `App/RootView.swift`.
 *
 * Placeholder state machine -- there is no AuthenticationViewModel/Parse
 * session check wired up yet (see AuthenticationService.swift on iOS for
 * what that port still needs); this only demonstrates the screen shell
 * and Michigan-branded theme end to end.
 */
@Composable
fun RootScreen() {
    var authState by remember { mutableStateOf<AuthenticationState>(AuthenticationState.SignedOut) }

    Surface(
        modifier = Modifier.safeDrawingPadding(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Crossfade(targetState = authState, label = "authState") { state ->
            when (state) {
                is AuthenticationState.CheckingSession, is AuthenticationState.EndingSession -> LoadingScreen()
                is AuthenticationState.SignedOut -> WelcomeScreen(
                    onContinue = {
                        authState = AuthenticationState.SignedIn(AuthenticatedUserPlaceholder)
                    },
                )
                is AuthenticationState.SignedIn -> HomeScreen(
                    onSignOut = { authState = AuthenticationState.SignedOut },
                )
            }
        }
    }
}

@Composable
private fun LoadingScreen() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
    }
}
