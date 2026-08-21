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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch authViewModel.state {
            case .checkingSession, .endingSession:
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
        // Without this, switching between the cases above (e.g. Home ->
        // the .endingSession spinner -> Welcome on sign-out) is an
        // instant cut -- SwiftUI has no reason to animate a plain
        // `switch` on its own. This crossfades every state change,
        // including sign-in and the initial checkingSession -> Welcome
        // launch transition, not just sign-out.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: authViewModel.state)
        // Onboarding -> Welcome is a separate switch within the same
        // `.signedOut` case above, driven by `hasCompletedOnboarding`
        // rather than `authViewModel.state` -- needs its own `.animation`
        // or it snaps instantly when onboarding is dismissed.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: hasCompletedOnboarding)
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
