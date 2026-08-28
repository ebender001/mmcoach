//
//  NewCaseViewModel.swift
//  MMCoach
//

import Foundation
import Combine

@MainActor
final class NewCaseViewModel: ObservableObject {
    @Published var narrativeText = "" {
        didSet {
            spellingSuggestions = medicalDictionary.possibleMisspellings(in: narrativeText)
        }
    }
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var spellingSuggestions: [String] = []
    /// Mirrors `dictation.dictationPhase`/`dictationErrorMessage`/
    /// `phiNoticeMessage` so the view only needs to observe this one
    /// object -- see observeDictation().
    @Published private(set) var dictationPhase: DictationPhase = .idle
    @Published var dictationErrorMessage: String?
    @Published var phiNoticeMessage: String?

    let dictation: DictationController

    private let medicalDictionary: MedicalDictionaryService
    private let phiFilter: PHIFilterService
    private var observationTasks: [Task<Void, Never>] = []

    private static let minimumNarrativeLength = 20

    var isDictating: Bool { dictationPhase != .idle }

    init(dictation: DictationController? = nil,
         medicalDictionary: MedicalDictionaryService? = nil,
         phiFilter: PHIFilterService? = nil) {
        let medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
        self.dictation = dictation ?? DictationController(medicalDictionary: medicalDictionary)
        self.medicalDictionary = medicalDictionary
        self.phiFilter = phiFilter ?? .shared
        self.dictation.onCorrectedText = { [weak self] text in
            self?.narrativeText = text
        }
        observeDictation()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    /// Enabled as soon as there's any typed/dictated text -- the stricter
    /// `minimumNarrativeLength` check happens on submit (see `submit()`),
    /// which surfaces a specific inline message instead of just leaving
    /// the button disabled with no explanation.
    var canContinue: Bool {
        dictationPhase == .idle && !isSubmitting
            && !narrativeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleDictation() async {
        await dictation.toggleDictation(currentText: narrativeText)
    }

    /// Submits the narrative and returns the created case, or nil on failure
    /// (in which case `errorMessage` is set and `narrativeText` is preserved).
    func submit() async -> MMCase? {
        errorMessage = nil
        let trimmed = narrativeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumNarrativeLength else {
            errorMessage = "Add a bit more detail before continuing."
            return nil
        }

        // Final on-device PHI screen before anything is sent to the
        // backend (which forwards the narrative to OpenAI) -- catches PHI
        // typed by hand, which dictation-time screening never saw. If
        // anything is found, show the trainee the redacted result instead
        // of silently submitting a rewritten narrative -- they can review
        // it and tap Continue again.
        let phiResult = phiFilter.redact(trimmed)
        if phiResult.hasFindings {
            narrativeText = phiResult.redactedText
            phiNoticeMessage = phiResult.noticeMessage
            return nil
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            return try await BackendService.createCase(narrative: trimmed)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
            return nil
        }
    }

    private func observeDictation() {
        let phaseTask = Task { [weak self] in
            guard let self else { return }
            for await phase in self.dictation.$dictationPhase.values {
                self.dictationPhase = phase
            }
        }
        let errorTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.dictation.$dictationErrorMessage.values {
                self.dictationErrorMessage = message
            }
        }
        let phiTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.dictation.$phiNoticeMessage.values {
                guard message != nil else { continue }
                self.phiNoticeMessage = message
            }
        }
        observationTasks = [phaseTask, errorTask, phiTask]
    }
}
