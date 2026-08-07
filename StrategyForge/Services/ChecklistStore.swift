//
//  ChecklistStore.swift
//  StrategyForge
//
//  Device-local persistence for launch checklists. Mirrors MemoryStore: an @Observable
//  @MainActor singleton, injectable storeDirectory for tests, atomic writes, tolerant decode.
//

import Foundation

@Observable
@MainActor
final class ChecklistStore {

    static let shared = ChecklistStore()

    @ObservationIgnored private let storeDirectory: URL
    private(set) var checklists: [LaunchChecklist] = []

    init(storeDirectory: URL = AppPaths.supportDirectory()) {
        self.storeDirectory = storeDirectory
        load()
    }

    /// The checklist attached to a project, if any.
    func checklist(forProject id: UUID) -> LaunchChecklist? {
        checklists.first { $0.projectID == id }
    }

    @discardableResult
    func add(_ checklist: LaunchChecklist) -> LaunchChecklist.ID {
        checklists.insert(checklist, at: 0)
        save()
        return checklist.id
    }

    func update(_ checklist: LaunchChecklist) {
        guard let i = checklists.firstIndex(where: { $0.id == checklist.id }) else { return }
        checklists[i] = checklist
        save()
    }

    func delete(_ id: LaunchChecklist.ID) {
        checklists.removeAll { $0.id == id }
        save()
    }

    /// Toggle one item's done state inside a checklist and persist.
    func toggle(checklist cid: LaunchChecklist.ID, item iid: ChecklistItem.ID) {
        guard let ci = checklists.firstIndex(where: { $0.id == cid }) else { return }
        for si in checklists[ci].sections.indices {
            if let ii = checklists[ci].sections[si].items.firstIndex(where: { $0.id == iid }) {
                checklists[ci].sections[si].items[ii].done.toggle()
                save()
                return
            }
        }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        static let currentVersion = 1
        var schemaVersion: Int
        var checklists: [LaunchChecklist]
        init(checklists: [LaunchChecklist], schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion; self.checklists = checklists
        }
        enum CodingKeys: String, CodingKey { case schemaVersion, checklists }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            checklists = try c.decodeIfPresent([LaunchChecklist].self, forKey: .checklists) ?? []
        }
    }

    private var storeURL: URL { storeDirectory.appendingPathComponent("checklists.json") }

    func save() {
        do {
            let data = try JSONEncoder().encode(Persisted(checklists: checklists))
            try data.write(to: storeURL, options: .atomic)
        } catch { /* best-effort; a checklist is recoverable content */ }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        checklists = decoded.checklists
    }
}
