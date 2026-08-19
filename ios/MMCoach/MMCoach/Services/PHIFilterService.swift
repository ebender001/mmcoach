//
//  PHIFilterService.swift
//  MMCoach
//
//  On-device-only screen for PHI in anything the trainee dictates or types,
//  applied before that text is allowed to reach ANY network call -- the
//  dictation-correction, case-creation, and answer-submission Cloud
//  Functions all forward text to OpenAI, so all of them are in scope, not
//  just dictation. Nothing in this file makes a network call; it only
//  reads/rewrites a local string using on-device frameworks (NaturalLanguage,
//  NSDataDetector) -- see Apple's docs confirming both run fully on-device.
//
//  Scope is deliberately narrow, matching what was asked: patient/staff
//  names, hospital/institution names, and procedure dates. This is NOT a
//  full HIPAA Safe Harbor de-identification (that also covers ages >89,
//  exact addresses, MRNs, phone numbers, etc.) -- trainees still need to
//  follow their institution's case-presentation norms; this is a safety
//  net that catches obvious slips, not a substitute for that judgment.
//
//  IMPORTANT LIMITATION: this only protects TEXT. It cannot protect audio
//  already sent to Apple's speech-recognition servers during server-based
//  dictation (see SpeechRecognitionService) -- by the time a spoken name
//  reaches this filter as transcribed text, the audio containing it has
//  already left the device. There is no way to filter audio content before
//  sending it without defeating the purpose of speech recognition, so the
//  only way to fully close that gap is to force on-device-only recognition
//  (which drops contextualStrings support -- see that file's header).
//

import Foundation
import NaturalLanguage

struct PHIFinding: Equatable {
    enum Category: String, CaseIterable {
        case name
        case institution
        case date

        var label: String {
            switch self {
            case .name: return "a patient or staff name"
            case .institution: return "a hospital or institution name"
            case .date: return "a specific date"
            }
        }

        fileprivate var placeholder: String {
            switch self {
            case .name: return "[name removed]"
            case .institution: return "[institution removed]"
            case .date: return "[date removed]"
            }
        }
    }

    let category: Category
    let originalText: String
}

struct PHIFilterResult {
    let redactedText: String
    let findings: [PHIFinding]

    var hasFindings: Bool { !findings.isEmpty }

    /// A short, human-readable summary of what was removed, grouped by
    /// category -- never repeats the actual redacted text back, since that
    /// would defeat the point of removing it.
    var noticeMessage: String? {
        guard !findings.isEmpty else { return nil }
        let categories = Set(findings.map { $0.category })
        let labels = PHIFinding.Category.allCases.filter { categories.contains($0) }.map(\.label)

        let joinedLabels: String
        switch labels.count {
        case 1: joinedLabels = labels[0]
        case 2: joinedLabels = "\(labels[0]) and \(labels[1])"
        default: joinedLabels = labels.dropLast().joined(separator: ", ") + ", and " + labels[labels.count - 1]
        }

        return "We removed what looked like \(joinedLabels) before sending this. Please describe cases without patient names, staff or institution names, or specific dates."
    }
}

@MainActor
final class PHIFilterService {
    static let shared = PHIFilterService()

    /// Medical eponyms a generic English name detector can mistake for a
    /// patient/staff name (e.g. "Whipple procedure", "Crohn's disease") --
    /// never redacted even when they look like a person's name. Several of
    /// these (Whipple, Courvoisier, Richter, Barrett) aren't in either
    /// bundled word list at all, so `medicalDictionary.contains` alone
    /// wouldn't catch them. Hand-curated and expected to grow, same
    /// pattern as Specialty.commonAbbreviations.
    private static let eponymAllowlist: Set<String> = [
        "whipple", "crohn", "crohn's", "nissen", "zenker", "barrett", "barrett's",
        "courvoisier", "richter", "meckel", "ladd", "kocher", "pringle",
        "billroth", "roux", "heller", "hartmann", "miles", "graham",
        "boerhaave", "mallory", "mallory-weiss", "weiss", "curling", "cushing",
        "virchow", "charcot", "murphy", "mcburney", "rovsing", "cullen",
        "ranson", "sengstaken", "blakemore"
    ]

    /// Backstop for hospital/clinic names NLTagger's general-purpose NER
    /// unreliably misses entirely (confirmed empirically: it missed
    /// "Massachusetts General Hospital" and "Mount Sinai Hospital" outright,
    /// and mis-split "St. Mary's Hospital"). Matches a run of capitalized
    /// words immediately followed by a common institutional-name keyword,
    /// which real generic mentions ("the hospital", "an outside hospital")
    /// don't match since they aren't capitalized.
    private static let institutionKeywordPattern: NSRegularExpression = {
        let pattern = #"\b(?:[A-Z][A-Za-z'.]*\s+){1,6}(?:Hospital|Clinic|Medical Center|Health System|Infirmary|Institute|Health Center)\b"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private let medicalDictionary: MedicalDictionaryService

    init(medicalDictionary: MedicalDictionaryService? = nil) {
        self.medicalDictionary = medicalDictionary ?? .shared(for: SpecialtyStore.shared.selected)
    }

    func redact(_ text: String) -> PHIFilterResult {
        guard !text.isEmpty else { return PHIFilterResult(redactedText: text, findings: []) }

        var matches: [(range: NSRange, category: PHIFinding.Category)] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            for match in dateDetector.matches(in: text, range: fullRange) {
                matches.append((match.range, .date))
            }
        }

        for match in Self.institutionKeywordPattern.matches(in: text, range: fullRange) {
            matches.append((match.range, .institution))
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag else { return true }
            let category: PHIFinding.Category
            switch tag {
            case .personalName: category = .name
            case .organizationName: category = .institution
            default: return true
            }
            let matchedWord = String(text[range])
            guard !Self.isKnownMedicalTerm(matchedWord, in: self.medicalDictionary) else { return true }
            matches.append((NSRange(range, in: text), category))
            return true
        }

        // Sort by start position, then by longest-first so that when two
        // sources (e.g. the institution regex and NLTagger) both match
        // starting at the same point, the more complete match deterministically
        // wins the overlap-exclusion below, regardless of sort stability.
        matches.sort {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location
                : $0.range.length > $1.range.length
        }
        var nonOverlapping: [(range: NSRange, category: PHIFinding.Category)] = []
        var lastEnd = 0
        for match in matches where match.range.location >= lastEnd {
            nonOverlapping.append(match)
            lastEnd = match.range.location + match.range.length
        }

        guard !nonOverlapping.isEmpty else {
            return PHIFilterResult(redactedText: text, findings: [])
        }

        var findings: [PHIFinding] = []
        var redacted = ""
        var cursor = 0
        for match in nonOverlapping {
            redacted += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            findings.append(PHIFinding(category: match.category, originalText: nsText.substring(with: match.range)))
            redacted += match.category.placeholder
            cursor = match.range.location + match.range.length
        }
        redacted += nsText.substring(from: cursor)

        return PHIFilterResult(redactedText: redacted, findings: findings)
    }

    private static func isKnownMedicalTerm(_ word: String, in dictionary: MedicalDictionaryService) -> Bool {
        eponymAllowlist.contains(word.lowercased()) || dictionary.contains(word)
    }
}
