//
//  EmailAuthenticationView.swift
//  MMCoach
//
//  Presented from WelcomeView's "Continue with Email". A single sheet
//  with a segmented Sign In / Create Account switch rather than two
//  separate screens, since the fields mostly overlap.
//

import SwiftUI

struct EmailAuthenticationView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var isPresentingPasswordReset = false

    private enum Field: Hashable {
        case email, password, confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modePicker
                    formCard

                    if let message = viewModel.formErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    submitButton
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.warmBackground)
            .navigationTitle(viewModel.emailMode == .signIn ? "Sign In" : "Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .onAppear { viewModel.resetEmailForm() }
        .onChange(of: viewModel.state) { _, newValue in
            if case .signedIn = newValue { dismiss() }
        }
        .sheet(isPresented: $isPresentingPasswordReset) {
            PasswordResetView(viewModel: viewModel)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.emailMode) {
            Text("Sign In").tag(EmailAuthMode.signIn)
            Text("Create Account").tag(EmailAuthMode.createAccount)
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.emailMode) { _, _ in viewModel.resetEmailForm() }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(
                title: "Email address",
                error: viewModel.emailFieldError
            ) {
                TextField("you@hospital.edu", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            field(
                title: "Password",
                error: viewModel.passwordFieldError
            ) {
                passwordField
            }

            if viewModel.emailMode == .signIn {
                forgotPasswordButton
            }

            if viewModel.emailMode == .createAccount {
                field(
                    title: "Confirm password",
                    error: viewModel.confirmPasswordFieldError
                ) {
                    confirmPasswordField
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var passwordField: some View {
        HStack {
            Group {
                if viewModel.isPasswordVisible {
                    TextField("At least 8 characters", text: $viewModel.password)
                } else {
                    SecureField("At least 8 characters", text: $viewModel.password)
                }
            }
            .textContentType(viewModel.emailMode == .signIn ? .password : .newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .password)
            .submitLabel(viewModel.emailMode == .signIn ? .go : .next)
            .onSubmit {
                if viewModel.emailMode == .createAccount {
                    focusedField = .confirmPassword
                } else {
                    submit()
                }
            }

            revealButton(isVisible: $viewModel.isPasswordVisible, fieldLabel: "password")
        }
    }

    private var confirmPasswordField: some View {
        HStack {
            Group {
                if viewModel.isPasswordVisible {
                    TextField("Re-enter password", text: $viewModel.confirmPassword)
                } else {
                    SecureField("Re-enter password", text: $viewModel.confirmPassword)
                }
            }
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .confirmPassword)
            .submitLabel(.go)
            .onSubmit { submit() }

            revealButton(isVisible: $viewModel.isPasswordVisible, fieldLabel: "confirm password")
        }
    }

    private func revealButton(isVisible: Binding<Bool>, fieldLabel: String) -> some View {
        Button {
            isVisible.wrappedValue.toggle()
        } label: {
            Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                .foregroundStyle(Color.slateText)
        }
        .accessibilityLabel(isVisible.wrappedValue ? "Hide \(fieldLabel)" : "Show \(fieldLabel)")
    }

    private func field(
        title: String,
        error: String?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.slateText)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(error == nil ? Color.primary.opacity(0.08) : Color.red.opacity(0.6), lineWidth: 1)
                )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var forgotPasswordButton: some View {
        Button("Forgot password?") {
            viewModel.resetPasswordResetForm()
            viewModel.resetEmail = viewModel.email
            isPresentingPasswordReset = true
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.michiganBlueText)
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            if viewModel.isSubmittingEmailForm {
                ProgressView()
                    .tint(.white)
            } else {
                Text(viewModel.emailMode == .signIn ? "Sign In" : "Create Account")
            }
        }
        .buttonStyle(.michiganProminent)
        .disabled(viewModel.isSubmittingEmailForm)
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submitEmailForm() }
    }
}

#Preview("Sign In") {
    let viewModel = AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                             appleSignIn: PreviewAppleSignInService())
    viewModel.emailMode = .signIn
    return EmailAuthenticationView(viewModel: viewModel)
}

#Preview("Create Account") {
    let viewModel = AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                             appleSignIn: PreviewAppleSignInService())
    viewModel.emailMode = .createAccount
    return EmailAuthenticationView(viewModel: viewModel)
}

