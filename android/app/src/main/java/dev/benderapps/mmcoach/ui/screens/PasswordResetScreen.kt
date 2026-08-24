package dev.benderapps.mmcoach.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.benderapps.mmcoach.viewmodels.AuthenticationViewModel

/**
 * Reached from EmailAuthScreen's "Forgot password?". Uses Parse's
 * existing password-reset email (see ParseAuthenticationService).
 * Mirrors iOS `Views/Authentication/PasswordResetView.swift`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PasswordResetScreen(
    viewModel: AuthenticationViewModel,
    onDismiss: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Forgot Password") },
            navigationIcon = {
                TextButton(onClick = onDismiss) {
                    Text(if (viewModel.resetConfirmationMessage == null) "Cancel" else "Done")
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "Enter your account email and we'll send reset instructions.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            val confirmation = viewModel.resetConfirmationMessage
            if (confirmation != null) {
                Text(confirmation, style = MaterialTheme.typography.bodyLarge)
            } else {
                OutlinedTextField(
                    value = viewModel.resetEmail,
                    onValueChange = { viewModel.resetEmail = it },
                    label = { Text("Email address") },
                    singleLine = true,
                    isError = viewModel.resetEmailFieldError != null,
                    supportingText = viewModel.resetEmailFieldError?.let { { Text(it) } },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                )

                viewModel.resetErrorMessage?.let { message ->
                    Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyLarge)
                }

                Button(
                    onClick = { viewModel.sendPasswordReset() },
                    enabled = !viewModel.isSendingResetLink,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) {
                    if (viewModel.isSendingResetLink) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary)
                    } else {
                        Text("Send Reset Link")
                    }
                }
            }
        }
    }
}
