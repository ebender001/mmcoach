//
//  WelcomeView.swift
//  MMCoach
//
//  Shown when there's no signed-in user (see RootView). "Continue with
//  Apple" uses Apple's native SwiftUI button, which owns presenting the
//  system Apple ID sheet itself -- this view only forwards the resulting
//  ASAuthorization to the view model, never touching AuthenticationServices
//  or Parse APIs directly.
//

import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresentingEmailAuth = false

    var body: some View {
        ZStack {
            Color.warmBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                header

                Spacer(minLength: 20)

                Text("Prepare clinical cases for M&M conference with a guided, structured workflow.")
                    .font(.body)
                    .foregroundStyle(Color.slateText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Spacer(minLength: 32)

                actions

                Text("By continuing, you agree to the Terms of Use and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(Color.slateText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $isPresentingEmailAuth) {
            EmailAuthenticationView(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("M&M Coach")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            Text("Case conference preparation")
                .font(.subheadline)
                .foregroundStyle(Color.slateText)
        }
    }

    private var actions: some View {
        VStack(spacing: 16) {
            appleButton

            if let message = viewModel.appleSignInErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Sign in with Apple error: \(message)")
            }

            orDivider

            Button {
                viewModel.resetEmailForm()
                isPresentingEmailAuth = true
            } label: {
                Text("Continue with Email")
            }
            .buttonStyle(.michiganProminent)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { await viewModel.handleAppleSignInResult(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(viewModel.isAppleSignInInProgress)
        .overlay {
            if viewModel.isAppleSignInInProgress {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.25))
                ProgressView()
                    .tint(.white)
            }
        }
        .accessibilityLabel("Continue with Apple")
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            dividerLine
            Text("OR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.slateText)
            dividerLine
        }
        .accessibilityHidden(true)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }
}

#Preview("Signed out") {
    WelcomeView(viewModel: AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                                    appleSignIn: PreviewAppleSignInService()))
}

#Preview("Apple sign-in error") {
    let viewModel = AuthenticationViewModel(authService: PreviewAuthenticationService(),
                                             appleSignIn: PreviewAppleSignInService())
    viewModel.appleSignInErrorMessage = "Sign in with Apple didn't complete. Please try again."
    return WelcomeView(viewModel: viewModel)
}
