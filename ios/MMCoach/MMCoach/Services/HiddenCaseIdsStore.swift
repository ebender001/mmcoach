//
//  HiddenCaseIdsStore.swift
//  MMCoach
//
//  The Recent Cases list itself is sourced entirely from the backend (see
//  BackendService.listCases) -- this store holds only a small local
//  denylist of case ids the trainee has swiped away, so "removing" a case
//  from Recent Cases stays a per-device UI preference (matching the old
//  local-index behavior) rather than deleting the case's backend record.
//

import Foundation

struct HiddenCaseIdsStore {
    private let defaults: UserDefaults
    private let storageKey = "dev.benderapps.MMCoach.hiddenCaseIds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func hide(id: String) {
        var ids = all()
        ids.insert(id)
        defaults.set(Array(ids), forKey: storageKey)
    }
}
