//
//  CaseSummaryView.swift
//  MMCoach
//
//  The prepared case's home: one screen, four sections (Case, Prepare,
//  Questions, References) switched with a segmented control. These
//  sections are NOT top-level app destinations -- they belong to this one
//  case, so they don't use the app's primary navigation.
//

import SwiftUI

struct CaseSummaryView: View {
    @StateObject private var viewModel: CaseSummaryViewModel
    @State private var selectedSection = Section.polishedCase
    @Binding var path: [AppRoute]

    init(viewModel: @autoclosure @escaping () -> CaseSummaryViewModel, path: Binding<[AppRoute]>) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _path = path
    }

    private enum Section: String, CaseIterable, Identifiable {
        case polishedCase = "Case"
        case prepare = "Prepare"
        case questions = "Questions"
        case references = "References"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if viewModel.isLoading {
                LoadingView(message: "Loading your case…")
            } else if let errorMessage = viewModel.errorMessage, viewModel.polishedNarrative.isEmpty {
                ErrorView(message: errorMessage) {
                    Task { await viewModel.loadIfNeeded() }
                }
            } else {
                sectionContent
            }
        }
        .navigationTitle("Prepared Case")
        .navigationBarTitleDisplayMode(.inline)
        // This is a terminal screen -- stepping "back" into the interview
        // that produced an already-finalized case isn't a meaningful
        // action, so the only way out is the explicit Done button, which
        // always returns straight to Home in one step regardless of how
        // deep the stack was when this screen was reached (new-case flow
        // vs. opening an already-completed case from Recent Cases).
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { path = [] }
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .polishedCase:
            PolishedCaseView(narrative: viewModel.polishedNarrative)
        case .prepare:
            DiscussionPrepView(topics: viewModel.discussionPreparation)
        case .questions:
            FacultyQuestionsView(questions: viewModel.likelyFacultyQuestions)
        case .references:
            ReferencesView(references: viewModel.references)
        }
    }
}

#Preview {
    NavigationStack {
        CaseSummaryView(
            viewModel: CaseSummaryViewModel(
                caseId: "preview",
                initialCase: MMCase(
                    id: "preview",
                    status: .completed,
                    polishedNarrative: "A 68-year-old man underwent CABG x3. He was initially stable in the ICU, but approximately four hours after arrival became hypotensive with increasing chest tube output. He was resuscitated with blood products and returned to the operating room, where a bleeding vessel was identified and controlled.",
                    discussionPreparation: [
                        DiscussionTopic(topic: "Timing of re-exploration",
                                         whyItMatters: "The patient had persistent bleeding with increasing transfusion requirements.",
                                         prepareToDiscuss: "Thresholds for surgical re-exploration and whether earlier intervention might have been appropriate.")
                    ],
                    likelyFacultyQuestions: [
                        "What prompted the decision to obtain imaging at that point?",
                        "At what point would you consider operative re-exploration?"
                    ],
                    references: [
                        ReferenceItem(topic: "Postoperative bleeding after cardiac surgery",
                                      searchIntent: "Current guideline or high-quality evidence regarding indications and timing for surgical re-exploration.",
                                      citation: nil,
                                      verified: false)
                    ]
                )
            ),
            path: .constant([])
        )
    }
}
