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

    var body: some View {
        Group {
            switch authViewModel.state {
            case .checkingSession:
                loadingView
            case .signedOut:
                WelcomeView(viewModel: authViewModel)
            case .signedIn(let user):
                HomeView(currentUser: user) {
                    Task { await authViewModel.signOut() }
                }
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
