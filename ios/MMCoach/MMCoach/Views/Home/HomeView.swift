//
//  HomeView.swift
//  MMCoach
//
//  App entry screen and root of the single NavigationStack. Everything
//  after Home (new case intake, the interview, the prepared case) belongs
//  to one case-preparation workflow, so it's modeled as pushes onto this
//  stack rather than as separate tab-bar destinations.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var specialtyStore = SpecialtyStore.shared
    @State private var path: [AppRoute] = []
    @State private var isPresentingAccount = false

    /// The signed-in user, a sign-out action, and an account-deletion
    /// action, all supplied by `RootView`. Optional (rather than a
    /// required non-Optional `AuthenticatedUser`) so `HomeView()` keeps
    /// working unchanged in previews/tests that don't care about the
    /// account area.
    private let currentUser: AuthenticatedUser?
    private let onSignOut: (() -> Void)?
    private let onDeleteAccount: (() async throws -> Void)?

    init(currentUser: AuthenticatedUser? = nil,
         onSignOut: (() -> Void)? = nil,
         onDeleteAccount: (() async throws -> Void)? = nil) {
        self.currentUser = currentUser
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _viewModel = StateObject(wrappedValue: HomeViewModel())
    }

    init(currentUser: AuthenticatedUser? = nil,
         onSignOut: (() -> Void)? = nil,
         onDeleteAccount: (() async throws -> Void)? = nil,
         viewModel: HomeViewModel) {
        self.currentUser = currentUser
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    header
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    SpecialtySelectionCard(selection: $specialtyStore.selected)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets(top: 4, bottom: 4))
                .listRowBackground(Color.clear)

                Section {
                    NewCaseActionCard {
                        Task {
                            if await viewModel.startNewCase() {
                                path.append(.newCase)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets(top: 4, bottom: 6))
                .listRowBackground(Color.clear)

                Section {
                    PrivacyReminder()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets(top: 0, bottom: 16))
                .listRowBackground(Color.clear)

                Section {
                    recentCasesHeader
                } header: { EmptyView() }
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets(top: 0, bottom: 4))
                    .listRowBackground(Color.clear)

                if viewModel.recentCases.isEmpty {
                    Section {
                        RecentCasesEmptyState()
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets(top: 0, bottom: 4))
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.recentCases) { record in
                            Button {
                                open(record)
                            } label: {
                                RecentCaseRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets(top: 4, bottom: 4))
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: viewModel.deleteRecentCases)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground)
            // On the List (the NavigationStack's root content), not the
            // NavigationStack itself -- the stack container only appears
            // once for the app's lifetime, so an .onAppear there fires
            // exactly once at launch and never again as the user
            // navigates back to Home. Attached here, it fires every time
            // Home becomes the visible screen again (including after the
            // "Done" pop-to-root from CaseSummaryView), which is what
            // actually keeps a newly created/updated case's Recent Cases
            // entry current without restarting the app.
            .onAppear { viewModel.refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                if onSignOut != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isPresentingAccount = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel("Account")
                    }
                }
                if !viewModel.recentCases.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $isPresentingAccount) {
                AccountView(user: currentUser, onDeleteAccount: onDeleteAccount) {
                    isPresentingAccount = false
                    onSignOut?()
                }
            }
            .sheet(isPresented: $viewModel.isPresentingPaywall, onDismiss: {
                // Runs after the sheet has actually finished closing, so
                // this push never races the dismiss animation (see
                // HomeViewModel.paywallDidUnlockAccess()).
                if viewModel.consumePaywallUnlock() {
                    path.append(.newCase)
                }
            }) {
                PaywallView {
                    viewModel.paywallDidUnlockAccess()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("M & M Coach")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text("Case conference preparation")
                .font(.subheadline)
                .foregroundStyle(Color.slateText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var recentCasesHeader: some View {
        Text("Recent Cases")
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func rowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20)
    }

    private func open(_ record: RecentCaseRecord) {
        switch record.status {
        case .completed:
            path.append(.summary(caseId: record.id, initialCase: nil))
        case .collectingInformation, .readyToFinalize:
            path.append(.interview(caseId: record.id, initialCase: nil))
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .newCase:
            NewCaseView(path: $path)
        case .interview(let caseId, let initialCase):
            CaseInterviewView(viewModel: CaseInterviewViewModel(caseId: caseId, initialCase: initialCase),
                               path: $path)
        case .summary(let caseId, let initialCase):
            CaseSummaryView(viewModel: CaseSummaryViewModel(caseId: caseId, initialCase: initialCase),
                             path: $path)
        }
    }
}

#if DEBUG
private enum HomeViewPreviewFactory {
    static func populated() -> HomeView {
        let store = RecentCasesStore(defaults: {
            let defaults = UserDefaults(suiteName: "HomeView.Populated.Preview")!
            defaults.removePersistentDomain(forName: "HomeView.Populated.Preview")
            return defaults
        }())
        for record in [
            RecentCaseRecord(id: "1", title: "68-year-old man, CABG x3, postoperative bleeding", createdAt: Date(), status: .collectingInformation),
            RecentCaseRecord(id: "2", title: "54-year-old woman, laparoscopic cholecystectomy, bile leak", createdAt: Date().addingTimeInterval(-86_400), status: .readyToFinalize),
            RecentCaseRecord(id: "3", title: "72-year-old man, AAA repair, postoperative MI", createdAt: Date().addingTimeInterval(-172_800), status: .completed)
        ] {
            store.upsert(record)
        }
        return HomeView(viewModel: HomeViewModel(store: store))
    }
}

#Preview("Empty") {
    HomeView()
}

#Preview("Populated") {
    HomeViewPreviewFactory.populated()
}
#endif
