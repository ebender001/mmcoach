//
//  RecentCasesStore.swift
//  MMCoach
//
//  Small local persistence layer backing the Home screen's "Recent Cases"
//  list. There is no backend case-listing Cloud Function in the MVP, so
//  this keeps a lightweight on-device index (id, title snippet, date,
//  status) that view models update as a case progresses. The case's real
//  content always lives on the backend and is fetched fresh via
//  BackendService when a case is opened.
//

import Foundation

struct RecentCasesStore {
    private let defaults: UserDefaults
    private let storageKey = "dev.benderapps.MMCoach.recentCases"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAll() -> [RecentCaseRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentCaseRecord].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func upsert(_ record: RecentCaseRecord) {
        var records = loadAll()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        persist(records)
    }

    func updateStatus(id: String, status: CaseStatus) {
        var records = loadAll()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = status
        persist(records)
    }

    /// Removes a case from the local index only. The case itself (and its
    /// backend record) is untouched -- this just stops it from appearing
    /// in "Recent Cases".
    func remove(id: String) {
        persist(loadAll().filter { $0.id != id })
    }

    private func persist(_ records: [RecentCaseRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
