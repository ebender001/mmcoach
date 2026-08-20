//
//  AccountView.swift
//  MMCoach
//
//  The MVP account area: who's signed in, and Sign Out. Presented as a
//  sheet from HomeView's toolbar (see HomeView's account button).
//  Deliberately minimal -- no profile editing, no account deletion (see
//  backend/README.md "Remaining backend work" for why).
//

import StoreKit
import SwiftUI

struct AccountView: View {
    let user: AuthenticatedUser?
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var isPresentingManageSubscriptions = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Signed in with") {
                        Label(signInMethodText, systemImage: signInMethodIcon)
                    }
                    if let email = user?.email {
                        LabeledContent("Email", value: email)
                    }
                }

                Section {
                    Button {
                        isPresentingManageSubscriptions = true
                    } label: {
                        Label("Manage Subscription", systemImage: "creditcard")
                    }
                } footer: {
                    // Apple owns auto-renewal/cancellation -- this only
                    // opens Apple's own subscription-management UI, never
                    // a manual "renew" control of our own.
                    Text("Opens Apple's subscription management, where you can view, change, or cancel your M & M Coach subscription.")
                }

                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        HStack {
                            Text("Sign Out")
                            if isSigningOut {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSigningOut)
                }

                Section {
                    Text("Do not include patient identifiers.")
                        .font(.caption)
                        .foregroundStyle(Color.slateText)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .manageSubscriptionsSheet(isPresented: $isPresentingManageSubscriptions)
        }
    }

    private var signInMethodText: String {
        switch user?.signInMethod {
        case .apple: "Apple"
        case .email, .none: "Email"
        }
    }

    private var signInMethodIcon: String {
        switch user?.signInMethod {
        case .apple: "applelogo"
        case .email, .none: "envelope"
        }
    }

    private func signOut() {
        isSigningOut = true
        onSignOut()
    }
}

#Preview("Email account") {
    AccountView(user: .preview, onSignOut: {})
}

#Preview("Apple account") {
    AccountView(user: .previewApple, onSignOut: {})
}
