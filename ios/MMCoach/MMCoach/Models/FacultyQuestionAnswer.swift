//
//  FacultyQuestionAnswer.swift
//  MMCoach
//
//  Returned by mmAnswerFacultyQuestion -- a live, on-demand model answer to
//  one of the case's own likely faculty questions. Distinct from
//  MMCase.likelyFacultyQuestions, which only stores the question text;
//  this is generated fresh each time and never persisted onto the case.
//

import Foundation

struct FacultyQuestionAnswer: Decodable {
    let question: String
    let answer: String
}
