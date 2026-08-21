//
//  PasswordResetView.swift
//  MMCoach
//
//  Reached from EmailAuthenticationView's "Forgot password?". Uses Parse's
//  existing password-reset email (ParseUser.passwordReset(email:), see
//  ParseAuthenticationService) -- there is no separate reset service.
//

import SwiftUI

struct PasswordResetView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Forgot password?")
                        .font(.title3.weight(.semibold))
                    Text("Enter your account email and we'll send reset instructions.")
                        .font(.subheadline)
                        .foregroundStyle(Color.slateText)
                }

                if let confirmation = viewModel.resetConfirmationMessage {
                    confirmationCard(confirmation)
                } else {
                    formCard
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.warmBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.resetConfirmationMessage == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEmailFocused = false }
                }
            }
        }
        .onAppear { viewModel.resetPasswordResetForm() }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Email address")
                    .font(.caption)
                    .foregroundStyle(Color.slateText)

                TextField("you@hospital.edu", text: $viewModel.resetEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                viewModel.resetEmailFieldError == nil ? Color.primary.opacity(0.08) : Color.red.opacity(0.6),
                                lineWidth: 1
                            )
                    )

                if let error = viewModel.resetEmailFieldError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = viewModel.resetErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                send()
            } label: {
                if viewModel.isSendingResetLink {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Send Reset Link")
                }
            }
            .buttonStyle(.michiganProminent)
            .disabled(viewModel.isSendingResetLink)
        }
    }

    private func confirmationCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.mutedTeal)
                .font(.title3)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func send() {
        isEmailFocused = false
        Task { await viewModel.sendPasswordReset() }
    }
}

#if DEBUG
#Preview("Enter email") {
    let viewModel = AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                             appleSignIn: PreviewAppleSignInService())
    PasswordResetView(viewModel: viewModel)
}

#Preview("Confirmation") {
    let viewModel = AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                             appleSignIn: PreviewAppleSignInService())
    PasswordResetView(viewModel: viewModel)
        .task {
            // Runs after PasswordResetView's own onAppear (which resets
            // the form), so this reliably ends up as the visible state.
            viewModel.resetEmail = "trainee@hospital.edu"
            await viewModel.sendPasswordReset()
        }
}
#endif
