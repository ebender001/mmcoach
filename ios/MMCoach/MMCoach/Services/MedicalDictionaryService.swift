//
//  MedicalDictionaryService.swift
//  MMCoach
//
//  Wraps two bundled word lists plus a hand-curated abbreviation list, and
//  uses all three to:
//   1. Keep UITextChecker from flagging valid medical terms as misspelled.
//   2. Seed SFSpeechRecognitionRequest.contextualStrings (see
//      SpeechRecognitionService) with high-collision-risk abbreviations.
//   3. Automatically fix a narrow, high-confidence class of dictation
//      errors once a session finishes -- see correctedTranscript(_:).
//
//  The two word lists are trusted differently for (3). "MedicalDictionary"
//  (docs/en-us-openmedspel, https://www.medspel.com, GPL) is the full
//  ~48k-word general medical vocabulary: broad enough that a fuzzy match
//  against it can land on an obscure, unrelated real word by coincidence
//  (e.g. a garbled ASR fragment matching some rare eponym), so it's only
//  used for (1) -- never auto-applied. The specialty-specific list (see
//  Specialty.dictionaryResourceName -- CVTMedicalDictionary or
//  GenSurgMedicalDictionary, both curated by the MMCoach team from the same
//  source; see docs/ for the readable, section-organized originals) is
//  small enough that a close match is much more likely to be genuinely
//  correct, so it -- along with that specialty's abbreviations -- is
//  trusted for auto-apply.
//
//  Loading a specialty's word lists is one-time work per specialty (a few
//  ms), so instances are cached per Specialty via `shared(for:)` rather
//  than reloaded on every screen -- see SpecialtyStore for where the
//  current specialty selection lives.

import Foundation
import UIKit

final class MedicalDictionaryService {
    @MainActor private static var cache: [Specialty: MedicalDictionaryService] = [:]

    @MainActor
    static func shared(for specialty: Specialty) -> MedicalDictionaryService {
        if let existing = cache[specialty] { return existing }
        let instance = MedicalDictionaryService(specialty: specialty)
        cache[specialty] = instance
        return instance
    }

    let specialty: Specialty

    /// Bounded seed for contextualStrings. Apple documents keeping that
    /// property under ~100 phrases for best results, so this stays scoped
    /// to curated, evidence-backed terms rather than either full word list.
    var contextualStringSeed: [String] { specialty.commonAbbreviations + specialty.highRiskTerms }

    /// lowercase word -> canonical display form, across BOTH word lists
    /// plus abbreviations. Broad coverage for spell-check exemption --
    /// never used as an auto-correct match target.
    private let wordsByLowercase: [String: String]

    /// lowercase word -> canonical display form, specialty list +
    /// abbreviations only. The higher-trust vocabulary auto-correct is
    /// allowed to match against.
    private let autoCorrectWordsByLowercase: [String: String]
    /// lowercase word -> lowercase auto-correct words sharing the same
    /// first letter, used to prune candidates before running Levenshtein
    /// distance.
    private let autoCorrectBucketsByFirstLetter: [Character: [String]]
    private let lowercasedAbbreviations: [String]

    init(specialty: Specialty, resourceBundle: Bundle = .main) {
        self.specialty = specialty
        let generalWords = Self.loadWords(named: "MedicalDictionary", from: resourceBundle)
        let specialtyWords = Self.loadWords(named: specialty.dictionaryResourceName, from: resourceBundle)

        var allWords = generalWords
        allWords.merge(specialtyWords) { _, specialtyWord in specialtyWord }
        for abbreviation in specialty.commonAbbreviations {
            allWords[abbreviation.lowercased()] = abbreviation
        }
        wordsByLowercase = allWords

        var autoCorrectWords = specialtyWords
        for abbreviation in specialty.commonAbbreviations {
            autoCorrectWords[abbreviation.lowercased()] = abbreviation
        }
        autoCorrectWordsByLowercase = autoCorrectWords
        autoCorrectBucketsByFirstLetter = Dictionary(grouping: autoCorrectWords.keys) { $0.first ?? "?" }
        lowercasedAbbreviations = specialty.commonAbbreviations.map { $0.lowercased() }
    }

    func contains(_ word: String) -> Bool {
        wordsByLowercase[word.lowercased()] != nil
    }

    /// Words in `text` that the system spell checker considers misspelled
    /// and that aren't recognized medical terms. Order matches first
    /// occurrence in `text`.
    func possibleMisspellings(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let checker = UITextChecker()
        let nsText = text as NSString
        var results: [String] = []
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let misspelledRange = checker.rangeOfMisspelledWord(in: text,
                                                                  range: searchRange,
                                                                  startingAt: searchRange.location,
                                                                  wrap: false,
                                                                  language: "en_US")
            guard misspelledRange.location != NSNotFound else { break }

            let word = nsText.substring(with: misspelledRange)
            if !contains(word) {
                results.append(word)
            }

            let nextLocation = misspelledRange.location + misspelledRange.length
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return results
    }

    /// Best-effort automatic correction, meant to run once after a
    /// dictation session finishes (not on every partial result). It only
    /// rewrites two narrow, high-confidence patterns:
    ///  - a short ALL-CAPS token that's a single-edit typo of a known
    ///    medical abbreviation (e.g. "LED" -> "LAD")
    ///  - a longer token the system spell checker considers misspelled,
    ///    with exactly one close (<=1-2 edit) match in the dictionary
    /// Both patterns only match against the higher-trust auto-correct
    /// vocabulary (curated CVT terms + abbreviations), not the full ~48k-
    /// word general dictionary -- see the type-level comment for why.
    /// Anything ambiguous (a tie between two equally-close candidates) or
    /// not close enough is left untouched. This intentionally will NOT fix
    /// a whole in-vocabulary word swapped for another, e.g.
    /// "saphenous" -> "sadness": the two aren't close enough letter-for-
    /// letter to distinguish from an unrelated correct sentence, and by the
    /// time recognition has already dropped "saphenous" for an unrelated
    /// word, no trace of it is left in the text to recover. Fixing that
    /// class of error requires contextualStrings to take effect during
    /// recognition itself (see SpeechRecognitionService), not text
    /// correction after the fact.
    func correctedTranscript(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let checker = UITextChecker()
        let tokenPattern = try! NSRegularExpression(pattern: "[A-Za-z]+")
        let nsText = text as NSString
        let matches = tokenPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = ""
        var lastEnd = 0
        for match in matches {
            let range = match.range
            result += nsText.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
            result += correctedToken(nsText.substring(with: range), checker: checker)
            lastEnd = range.location + range.length
        }
        result += nsText.substring(from: lastEnd)
        return result
    }

    private func correctedToken(_ token: String, checker: UITextChecker) -> String {
        guard !contains(token) else { return token }

        // Short ALL-CAPS tokens: check against curated abbreviations
        // regardless of whether the system checker thinks they're
        // misspelled (an unrelated known abbreviation like "LED" isn't).
        if (2...5).contains(token.count), token == token.uppercased() {
            guard let match = closestMatch(for: token.lowercased(),
                                            candidates: lowercasedAbbreviations,
                                            maxDistance: 1) else { return token }
            return wordsByLowercase[match] ?? match.uppercased()
        }

        guard token.count >= 5 else { return token }

        let fullRange = NSRange(location: 0, length: (token as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(in: token, range: fullRange,
                                                              startingAt: 0, wrap: false, language: "en_US")
        guard misspelledRange.location != NSNotFound else { return token }

        let maxDistance = token.count <= 7 ? 1 : 2
        let candidates = token.lowercased().first.flatMap { autoCorrectBucketsByFirstLetter[$0] } ?? []
        guard let match = closestMatch(for: token.lowercased(), candidates: candidates, maxDistance: maxDistance) else {
            return token
        }
        return matchingCase(of: token, to: autoCorrectWordsByLowercase[match] ?? match)
    }

    /// The single candidate within `maxDistance` edits of `word`, or nil if
    /// there's no match or more than one equally-close candidate -- ties are
    /// left uncorrected rather than guessed at.
    private func closestMatch(for word: String, candidates: [String], maxDistance: Int) -> String? {
        var best: String?
        var bestDistance = maxDistance + 1
        var isTie = false

        for candidate in candidates {
            guard abs(candidate.count - word.count) <= maxDistance else { continue }
            let distance = levenshteinDistance(word, candidate)
            guard distance <= maxDistance else { continue }

            if distance < bestDistance {
                bestDistance = distance
                best = candidate
                isTie = false
            } else if distance == bestDistance {
                isTie = true
            }
        }

        return isTie ? nil : best
    }

    private func matchingCase(of original: String, to canonical: String) -> String {
        guard let originalFirst = original.first, let canonicalFirst = canonical.first,
              originalFirst.isUppercase != canonicalFirst.isUppercase else {
            return canonical
        }
        let adjustedFirst = originalFirst.isUppercase ? canonicalFirst.uppercased() : canonicalFirst.lowercased()
        return adjustedFirst + canonical.dropFirst()
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previousRow = Array(0...bChars.count)
        var currentRow = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            currentRow[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currentRow[j] = Swift.min(previousRow[j] + 1,
                                           currentRow[j - 1] + 1,
                                           previousRow[j - 1] + cost)
            }
            previousRow = currentRow
        }
        return previousRow[bChars.count]
    }

    private static func loadWords(named resourceName: String, from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        var words: [String: String] = [:]
        contents.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            words[trimmed.lowercased()] = trimmed
        }
        return words
    }
}
