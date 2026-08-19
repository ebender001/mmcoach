//
//  Specialty.swift
//  MMCoach
//
//  The surgical specialty a case belongs to, chosen once on the Home
//  screen (see SpecialtyStore) and used to pick which curated dictionary,
//  abbreviation list, and contextualStrings seed MedicalDictionaryService
//  loads -- see that type for why these need to be specialty-scoped rather
//  than one combined list.
//

import Foundation

enum Specialty: String, CaseIterable, Identifiable {
    case cardiothoracic
    case generalSurgery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cardiothoracic: return "Cardiothoracic Surgery"
        case .generalSurgery: return "General Surgery"
        }
    }

    /// Bundled resource name (see Resources/) of this specialty's curated
    /// word list -- the higher-trust vocabulary MedicalDictionaryService is
    /// willing to auto-correct against.
    var dictionaryResourceName: String {
        switch self {
        case .cardiothoracic: return "CVTMedicalDictionary"
        case .generalSurgery: return "GenSurgMedicalDictionary"
        }
    }

    /// Short abbreviations dictation frequently mishears as an unrelated,
    /// in-vocabulary everyday word (e.g. "LAD" -> "LED"). Not derived from
    /// either word list -- those are full medical terms, not acronyms --
    /// so these are maintained by hand and expected to grow per specialty.
    var commonAbbreviations: [String] {
        switch self {
        case .cardiothoracic:
            return [
                "LAD", "LCX", "LMCA", "RCA", "RCX", "CABG", "PCI", "PTCA",
                "MI", "STEMI", "NSTEMI", "CHF", "COPD", "DVT", "PE", "CVA", "TIA",
                "ICU", "ICD", "EKG", "ECG", "GERD", "IBD", "IBS", "UTI", "URI",
                "CAD", "HTN", "CKD", "AKI", "ESRD", "DKA", "ARDS", "GI", "GU",
                "ENT", "NPO", "PRN", "BID", "TID", "NSAID", "PPI", "ABG",
                "WBC", "RBC", "BUN", "INR", "PTT", "LVEF", "SAH", "SDH", "ICH"
            ]
        case .generalSurgery:
            // General-purpose ward/perioperative abbreviations that apply
            // regardless of specialty. No general-surgery-specific
            // abbreviations (e.g. procedure acronyms) are curated yet --
            // add them here as real dictation sessions surface repeat
            // errors, same as cardiothoracic's list was built.
            return [
                "GI", "GU", "ICU", "UTI", "URI", "COPD", "DVT", "PE", "CVA", "TIA",
                "NPO", "PRN", "BID", "TID", "NSAID", "PPI", "ABG",
                "WBC", "RBC", "BUN", "INR", "PTT"
            ]
        }
    }

    /// Full (non-abbreviation) terms/phrases confirmed, from real dictation
    /// sessions, to be repeatedly misheard as an unrelated common word.
    /// Seeds SFSpeechRecognitionRequest.contextualStrings alongside the
    /// abbreviations above -- see MedicalDictionaryService.
    var highRiskTerms: [String] {
        switch self {
        case .cardiothoracic:
            return [
                "saphenous", "mammary", "coronary",
                "saphenous vein graft", "internal mammary artery",
                "right coronary artery", "circumflex coronary artery"
            ]
        case .generalSurgery:
            // No evidence-backed terms yet -- see commonAbbreviations note.
            return []
        }
    }
}
