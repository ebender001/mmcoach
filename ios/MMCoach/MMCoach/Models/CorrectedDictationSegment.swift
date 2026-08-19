//
//  CorrectedDictationSegment.swift
//  MMCoach
//
//  Result of BackendService.correctDictation, mirroring mmCorrectDictation's
//  response shape (see backend/cloud/schemas/aiResponseSchemas.js).
//

import Foundation

struct CorrectedDictationSegment: Decodable {
    let correctedSegment: String
    let changes: [Change]

    struct Change: Decodable {
        let original: String
        let corrected: String
    }
}
