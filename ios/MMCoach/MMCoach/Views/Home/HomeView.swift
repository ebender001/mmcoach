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
    @StateObject private var viewModel = HomeViewModel()
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    startCaseButton

                    recentCasesSection
                }
                .padding()
            }
            .navigationTitle("MMCoach")
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .onAppear { viewModel.refresh() }
    }

    private var startCaseButton: some View {
        Button {
            path.append(.newCase)
        } label: {
            Label("Start New Case", systemImage: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var recentCasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Cases")
                .font(.headline)

            if viewModel.recentCases.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentCases) { record in
                        Button {
                            open(record)
                        } label: {
                            CaseRowView(record: record)
                        }
                        .buttonStyle(.plain)

                        if record.id != viewModel.recentCases.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Start your first case to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
            CaseSummaryView(viewModel: CaseSummaryViewModel(caseId: caseId, initialCase: initialCase))
        }
    }
}

#Preview {
    HomeView()
}
