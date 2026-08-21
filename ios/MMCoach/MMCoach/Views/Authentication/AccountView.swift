//
//  AccountView.swift
//  MMCoach
//
//  The account area: who's signed in, subscription management, sign out,
//  and account deletion. Presented as a sheet from HomeView's toolbar (see
//  HomeView's account button). Styled like Home's own cards
//  (.polishedCard(), warmBackground) rather than a plain system list.
//

import StoreKit
import SwiftUI

struct AccountView: View {
    let user: AuthenticatedUser?
    /// Optional so `AccountView(user:onSignOut:)` keeps working unchanged
    /// in previews/tests and any caller that doesn't wire up deletion --
    /// the card below is hidden entirely when this is `nil`, the same way
    /// HomeView gates its account button on `onSignOut` being present.
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
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    actionsCard

                    if let onDeleteAccount {
                        deleteAccountCard(onDeleteAccount)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.warmBackground)
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

    private var profileHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.mutedTeal.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: signInMethodIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.mutedTeal)
            }
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                if let email = user?.email {
                    Text(email)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                Text("Signed in with \(signInMethodText)")
                    .font(.footnote)
                    .foregroundStyle(Color.slateText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "creditcard", title: "Manage Subscription") {
                isPresentingManageSubscriptions = true
            }

            Divider().overlay(Color.primary.opacity(0.06))

            settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", isDestructive: true, isBusy: isSigningOut) {
                signOut()
            }
        }
        .polishedCard()
    }

    private func deleteAccountCard(_ action: @escaping () async throws -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsRow(icon: "trash", title: "Delete Account", isDestructive: true, isBusy: isDeletingAccount) {
                isPresentingDeleteConfirmation = true
            }

            if let deleteAccountErrorMessage {
                Text(deleteAccountErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("Permanently deletes your account and every case you've prepared. This cannot be undone. It does not cancel an active subscription -- see Manage Subscription above.")
                .font(.caption)
                .foregroundStyle(Color.slateText)
        }
        .polishedCard()
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                deleteAccount(using: action)
            }
            // Apple owns subscriptions -- we have no way to cancel one on
            // the person's behalf, so deleting the account here would
            // otherwise silently leave them still being billed with no
            // account left to use. This gives them a way out of the
            // dialog straight into Manage Subscription instead.
            Button("Manage Subscription First") {
                isPresentingManageSubscriptions = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and every case you've prepared. It does not cancel any active subscription -- Apple will continue to bill you unless you cancel that separately. This cannot be undone.")
        }
    }

    /// One tappable row inside a `.polishedCard()` -- an icon, a title,
    /// and either a busy spinner or a chevron (chevron omitted for
    /// destructive rows, which don't push to another screen).
    private func settingsRow(icon: String,
                              title: String,
                              isDestructive: Bool = false,
                              isBusy: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDestructive ? Color.red : Color.michiganBlueText)
                    .frame(width: 26, height: 26)

                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : .primary)

                Spacer(minLength: 0)

                if isBusy {
                    ProgressView()
                } else if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.slateText.opacity(0.6))
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
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
