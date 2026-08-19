//
//  SpecialtyStore.swift
//  MMCoach
//
//  The app's single current specialty selection, chosen on the Home
//  screen and persisted across launches. This is a genuine app-wide
//  setting (not per-screen state), so it's a shared singleton like
//  MedicalDictionaryService rather than something passed down through
//  navigation.
//

import Foundation
import Combine

@MainActor
final class SpecialtyStore: ObservableObject {
    static let shared = SpecialtyStore()

    private static let storageKey = "MMCoach.selectedSpecialty"
    static let defaultSpecialty: Specialty = .cardiothoracic
    private let defaults: UserDefaults

    @Published var selected: Specialty {
        didSet {
            defaults.set(selected.rawValue, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey), let saved = Specialty(rawValue: raw) {
            selected = saved
        } else {
            selected = Self.defaultSpecialty
        }
    }
}
