//
//  NewCaseViewModel.swift
//  MMCoach
//

import Foundation
import Combine

@MainActor
final class NewCaseViewModel: ObservableObject {
    @Published var narrativeText = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published var dictationErrorMessage: String?

    let speechService: SpeechRecognitionService

    private let store: RecentCasesStore
    private var narrativeBeforeDictation = ""
    private var observationTasks: [Task<Void, Never>] = []

    private static let minimumNarrativeLength = 20

    init(speechService: SpeechRecognitionService? = nil,
         store: RecentCasesStore? = nil) {
        self.speechService = speechService ?? SpeechRecognitionService()
        self.store = store ?? RecentCasesStore()
        observeSpeechService()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    var canContinue: Bool {
        !isSubmitting && narrativeText.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumNarrativeLength
    }

    func toggleDictation() async {
        if speechService.isRecording {
            speechService.stopDictation()
        } else {
            narrativeBeforeDictation = narrativeText
            await speechService.startDictation()
        }
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

        if speechService.isRecording {
            speechService.stopDictation()
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let created = try await BackendService.createCase(narrative: trimmed)
            store.upsert(RecentCaseRecord(id: created.id,
                                           title: Self.title(from: trimmed),
                                           createdAt: Date(),
                                           status: created.status))
            return created
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
            return nil
        }
    }

    private static func title(from narrative: String) -> String {
        let singleLine = narrative.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 60 ? String(singleLine.prefix(60)) + "…" : singleLine
    }

    private func observeSpeechService() {
        let transcriptTask = Task { [weak self] in
            guard let self else { return }
            for await sessionText in self.speechService.$sessionTranscript.values {
                guard !sessionText.isEmpty else { continue }
                self.narrativeText = self.narrativeBeforeDictation.isEmpty
                    ? sessionText
                    : self.narrativeBeforeDictation + " " + sessionText
            }
        }
        let recordingTask = Task { [weak self] in
            guard let self else { return }
            for await recording in self.speechService.$isRecording.values {
                self.isRecording = recording
            }
        }
        let errorTask = Task { [weak self] in
            guard let self else { return }
            for await dictationError in self.speechService.$error.values {
                self.dictationErrorMessage = dictationError?.errorDescription
            }
        }
        observationTasks = [transcriptTask, recordingTask, errorTask]
    }
}
