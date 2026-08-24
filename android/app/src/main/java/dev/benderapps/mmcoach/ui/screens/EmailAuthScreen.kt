package dev.benderapps.mmcoach.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import dev.benderapps.mmcoach.viewmodels.AuthenticationViewModel
import dev.benderapps.mmcoach.viewmodels.EmailAuthMode

/**
 * Sign In / Create Account form, reached from WelcomeScreen's "Continue
 * with Email". A single screen with a mode switch rather than two
 * separate screens, since the fields mostly overlap. Mirrors iOS
 * `Views/Authentication/EmailAuthenticationView.swift`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmailAuthScreen(
    viewModel: AuthenticationViewModel,
    onDismiss: () -> Unit,
    onForgotPassword: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text(if (viewModel.emailMode == EmailAuthMode.SIGN_IN) "Sign In" else "Create Account") },
            navigationIcon = { TextButton(onClick = onDismiss) { Text("Cancel") } },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            modePicker(viewModel)

            OutlinedTextField(
                value = viewModel.email,
                onValueChange = { viewModel.email = it },
                label = { Text("Email address") },
                singleLine = true,
                isError = viewModel.emailFieldError != null,
                supportingText = viewModel.emailFieldError?.let { { Text(it) } },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )

            passwordField(
                value = viewModel.password,
                onValueChange = { viewModel.password = it },
                label = "Password",
                isVisible = viewModel.isPasswordVisible,
                onToggleVisibility = { viewModel.isPasswordVisible = !viewModel.isPasswordVisible },
                error = viewModel.passwordFieldError,
            )

            if (viewModel.emailMode == EmailAuthMode.SIGN_IN) {
                TextButton(onClick = onForgotPassword) {
                    Text("Forgot password?")
                }
            }

            if (viewModel.emailMode == EmailAuthMode.CREATE_ACCOUNT) {
                passwordField(
                    value = viewModel.confirmPassword,
                    onValueChange = { viewModel.confirmPassword = it },
                    label = "Confirm password",
                    isVisible = viewModel.isPasswordVisible,
                    onToggleVisibility = { viewModel.isPasswordVisible = !viewModel.isPasswordVisible },
                    error = viewModel.confirmPasswordFieldError,
                )
            }

            viewModel.formErrorMessage?.let { message ->
                Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyLarge)
            }

            Button(
                onClick = { viewModel.submitEmailForm() },
                enabled = !viewModel.isSubmittingEmailForm,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
            ) {
                if (viewModel.isSubmittingEmailForm) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary)
                } else {
                    Text(if (viewModel.emailMode == EmailAuthMode.SIGN_IN) "Sign In" else "Create Account")
                }
            }
        }
    }
}

@Composable
private fun modePicker(viewModel: AuthenticationViewModel) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(
            selected = viewModel.emailMode == EmailAuthMode.SIGN_IN,
            onClick = {
                viewModel.emailMode = EmailAuthMode.SIGN_IN
                viewModel.resetEmailForm()
            },
            label = { Text("Sign In") },
        )
        FilterChip(
            selected = viewModel.emailMode == EmailAuthMode.CREATE_ACCOUNT,
            onClick = {
                viewModel.emailMode = EmailAuthMode.CREATE_ACCOUNT
                viewModel.resetEmailForm()
            },
            label = { Text("Create Account") },
        )
    }
}

@Composable
private fun passwordField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    isVisible: Boolean,
    onToggleVisibility: () -> Unit,
    error: String?,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        visualTransformation = if (isVisible) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            IconButton(onClick = onToggleVisibility) {
                Icon(
                    imageVector = if (isVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = if (isVisible) "Hide $label" else "Show $label",
                )
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
