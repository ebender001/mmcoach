//
//  FacultyQuestionAnswerViewModel.swift
//  MMCoach
//
//  Drives FacultyQuestionAnswerView: an on-demand AI-drafted answer for one
//  faculty question, triggered by tapping a card in FacultyQuestionsView.
//

import Combine
import Foundation

@MainActor
final class FacultyQuestionAnswerViewModel: ObservableObject {
    let question: String
    private let caseId: String

    @Published private(set) var answer: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    init(question: String, caseId: String) {
        self.question = question
        self.caseId = caseId
    }

    func loadAnswer() async {
        guard !isLoading, answer == nil else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            answer = try await BackendService.answerFacultyQuestion(caseId: caseId, question: question)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
        }
    }
}
