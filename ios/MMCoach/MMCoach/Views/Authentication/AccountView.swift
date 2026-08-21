//
//  AccountView.swift
//  MMCoach
//
//  The account area: who's signed in, subscription management, sign out,
//  and account deletion. Presented as a sheet from HomeView's toolbar (see
//  HomeView's account button).
//

import StoreKit
import SwiftUI

struct AccountView: View {
    let user: AuthenticatedUser?
    /// Optional so `AccountView(user:onSignOut:)` keeps working unchanged
    /// in previews/tests and any caller that doesn't wire up deletion --
    /// the section below is hidden entirely when this is `nil`, the same
    /// way HomeView gates its account button on `onSignOut` being present.
    let onDeleteAccount: (() async throws -> Void)?
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var isPresentingManageSubscriptions = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?

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

                if let onDeleteAccount {
                    Section {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Text("Delete Account")
                                if isDeletingAccount {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isDeletingAccount)

                        if let deleteAccountErrorMessage {
                            Text(deleteAccountErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Permanently deletes your account and every case you've prepared. This cannot be undone. It does not cancel an active subscription -- see Manage Subscription above.")
                    }
                    .confirmationDialog(
                        "Delete your account?",
                        isPresented: $isPresentingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Account", role: .destructive) {
                            deleteAccount(using: onDeleteAccount)
                        }
                        // Apple owns subscriptions -- we have no way to
                        // cancel one on the person's behalf, so deleting
                        // the account here would otherwise silently leave
                        // them still being billed with no account left to
                        // use. This gives them a way out of the dialog
                        // straight into Manage Subscription instead.
                        Button("Manage Subscription First") {
                            isPresentingManageSubscriptions = true
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes your account and every case you've prepared. It does not cancel any active subscription -- Apple will continue to bill you unless you cancel that separately. This cannot be undone.")
                    }
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

    private func deleteAccount(using action: @escaping () async throws -> Void) {
        deleteAccountErrorMessage = nil
        isDeletingAccount = true
        Task {
            do {
                try await action()
                // Success flips the app's auth state to .signedOut (see
                // RootView), which tears down HomeView -- and this sheet
                // along with it -- the same way Sign Out already works
                // today. No explicit dismiss() needed here.
            } catch let error as AuthenticationServiceError {
                deleteAccountErrorMessage = error.errorDescription
            } catch {
                deleteAccountErrorMessage = "Something went wrong. Please try again."
            }
            isDeletingAccount = false
        }
    }
}

#Preview("Email account") {
    AccountView(user: .preview, onDeleteAccount: {}, onSignOut: {})
}

#Preview("Apple account") {
    AccountView(user: .previewApple, onDeleteAccount: {}, onSignOut: {})
}

#Preview("Delete account fails") {
    AccountView(user: .preview, onDeleteAccount: {
        throw AuthenticationServiceError.network
    }, onSignOut: {})
}
