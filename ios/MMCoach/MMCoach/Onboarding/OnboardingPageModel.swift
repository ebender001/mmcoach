//
//  OnboardingPageModel.swift
//  MMCoach
//
//  Static content for the four first-launch onboarding pages (see
//  OnboardingView). Content lives here, not scattered across view files,
//  so the copy is easy to review/update in one place.
//

import Foundation

/// Which non-interactive illustration (see OnboardingPreviewSnippet) a page
/// shows below its body text, if any -- built from the same real UI each
/// page's copy is describing, so the promise is visible, not just stated.
enum OnboardingPreviewKind: Equatable {
    case none
    /// A non-interactive mock of Home's "Start a New Case" button.
    case startCaseButton
    /// A non-interactive mock of the case-narrative dictate/type card.
    case dictateCard
    /// A non-interactive mock of one interview question card.
    case questionCard
    /// The real three-step "how it works" recap (see HowItWorksStep /
    /// RecentCasesEmptyState).
    case howItWorksRecap
}

/// A short standalone line below a page's body text -- currently only the
/// final page uses these (the free-case note and the patient-identifier
/// reminder), styled differently on purpose: `.highlight` is positive
/// emphasis, `.reminder` reuses the same lock-icon caption treatment as
/// PrivacyReminder on Home, since it's the same warning.
struct OnboardingFootnote: Equatable {
    enum Style: Equatable {
        case highlight
        case reminder
    }

    let text: String
    let style: Style
}

struct OnboardingPageModel: Identifiable, Equatable {
    let id: Int
    let symbolName: String
    let title: String
    /// Shown directly under `title`, in the same spot HomeView's header
    /// uses for "Case conference preparation" -- only the welcome page
    /// uses this (to label the whole onboarding flow as a preview once,
    /// up front, rather than tagging every illustration individually).
    let subtitle: String?
    let bodyText: String
    let footnotes: [OnboardingFootnote]
    let preview: OnboardingPreviewKind

    init(id: Int,
         symbolName: String,
         title: String,
         subtitle: String? = nil,
         bodyText: String,
         footnotes: [OnboardingFootnote] = [],
         preview: OnboardingPreviewKind = .none) {
        self.id = id
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.bodyText = bodyText
        self.footnotes = footnotes
        self.preview = preview
    }
}

extension OnboardingPageModel {
    /// "M & M Coach" (spaced) on the welcome page matches the app's name
    /// everywhere else it's shown as a brand name (see Theme/HomeView);
    /// unspaced "M&M" elsewhere in this copy refers to the conference
    /// type itself, consistent with the rest of the app's copy.
    static let all: [OnboardingPageModel] = [
        OnboardingPageModel(
            id: 0,
            symbolName: "stethoscope",
            title: "M & M Coach",
            subtitle: "Preview",
            bodyText: "Prepare cases for conference with greater clarity and confidence.\n\nA focused workspace for surgical trainees preparing morbidity and mortality cases.",
            preview: .startCaseButton
        ),
        OnboardingPageModel(
            id: 1,
            symbolName: "mic.fill",
            title: "Start with the case",
            bodyText: "Dictate or type a clinical summary in your own words.\n\nNo lengthy forms. Begin with the story as you would describe it at conference.",
            preview: .dictateCard
        ),
        OnboardingPageModel(
            id: 2,
            symbolName: "text.bubble.fill",
            title: "Build a clear clinical timeline",
            bodyText: "Answer focused follow-up questions to clarify the event, management, and key decision points.",
            preview: .questionCard
        ),
        OnboardingPageModel(
            id: 3,
            symbolName: "doc.text.fill",
            title: "Arrive prepared",
            bodyText: "Review a polished case narrative, discussion topics, likely faculty questions, and relevant PubMed abstracts.",
            footnotes: [
                OnboardingFootnote(text: "Your first complete case preparation is free.", style: .highlight),
                OnboardingFootnote(text: "Do not include patient identifiers.", style: .reminder),
            ],
            preview: .howItWorksRecap
        ),
    ]
}
