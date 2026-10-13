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
import TipKit

/// Shown once, above the segmented control, the first time the Prepared
/// Case screen is seen -- the trainee's dictation becomes the polished
/// narrative on the "Case" tab, and the pencil in that tab's toolbar is
/// the only way back into it.
///
/// This can't be a `.popoverTip()` anchored to that pencil toolbar
/// button: SwiftUI bridges toolbar content to UIKit bar button items, and
/// that bridging doesn't carry the anchor-preference data `.popoverTip()`
/// needs to find its anchor, so the tip is silently never shown even
/// though TipKit itself reports it as eligible (confirmed via TipKit's
/// own debug log). An inline `TipView` with a downward arrow, placed
/// above the segmented control, is the reliable substitute for "pointing
/// at" that toolbar button.
struct EditNarrativeTip: Tip {
    var title: Text { Text("Edit Your Dictation") }
    var message: Text? { Text("You can edit your dictation here.") }
    var image: Image? { Image(systemName: "pencil") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

struct CaseSummaryView: View {
    @StateObject private var viewModel: CaseSummaryViewModel
    @State private var selectedSection = Section.polishedCase
    @Binding var path: [AppRoute]
    private let editNarrativeTip = EditNarrativeTip()

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
            if selectedSection == .polishedCase && !viewModel.isLoading {
                TipView(editNarrativeTip, arrowEdge: .top)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

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
            PolishedCaseView(
                narrative: viewModel.polishedNarrative,
                isSaving: viewModel.isSavingNarrative,
                onSave: { await viewModel.updatePolishedNarrative($0) }
            )
        case .prepare:
            DiscussionPrepView(topics: viewModel.discussionPreparation)
        case .questions:
            FacultyQuestionsView(questions: viewModel.likelyFacultyQuestions,
                                 caseId: viewModel.caseId,
                                 cachedAnswers: viewModel.facultyQuestionAnswers)
        case .references:
            ReferencesView(references: viewModel.references,
                            caseId: viewModel.caseId,
                            cachedLookups: viewModel.referenceLookups)
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
