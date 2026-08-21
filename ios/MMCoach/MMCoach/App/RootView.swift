//
//  RootView.swift
//  MMCoach
//
//  App root: decides between the Welcome/authentication flow and the MM
//  Coach home screen based on `AuthenticationViewModel.state`. See
//  MMCoachApp -- this is what replaced a bare `HomeView()` as the
//  WindowGroup's content.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    /// Device-local, not tied to any account -- onboarding doesn't require
    /// signing in, and must not reappear after a sign-out on a device
    /// that's already seen it (see the `.signedOut` case below, which
    /// only shows OnboardingView while this is still `false`).
    @AppStorage("MMCoach.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            switch authViewModel.state {
            case .checkingSession:
                loadingView
            case .signedOut:
                if hasCompletedOnboarding {
                    WelcomeView(viewModel: authViewModel)
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            case .signedIn(let user):
                HomeView(currentUser: user, onSignOut: {
                    Task { await authViewModel.signOut() }
                }, onDeleteAccount: {
                    try await authViewModel.deleteAccount()
                })
            }
        }
        .task { await authViewModel.refreshSession() }
    }

    private var loadingView: some View {
        ZStack {
            Color.warmBackground.ignoresSafeArea()
            ProgressView()
                .tint(Color.michiganBlueText)
        }
    }
}

#Preview {
    RootView()
}
