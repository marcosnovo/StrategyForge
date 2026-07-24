//
//  MemoryStore.swift
//  StrategyForge
//
//  Device-local persistence for Coral's cross-project knowledge base (the Learnings).
//  Mirrors LoopStore exactly: an @Observable @MainActor singleton, an injectable
//  storeDirectory for tests, a versioned + tolerant Persisted wrapper, atomic writes,
//  and a corrupt-file backup on unreadable data.
//
//  Ships device-local. CloudKit roaming (so learnings follow the user across Macs) is a
//  later, separate slice — ConfigSyncStore is hardcoded to PortableConfiguration and a
//  new store does not ride it automatically.
//

import Foundation

@Observable
@MainActor
final class MemoryStore {

    static let shared = MemoryStore()

    /// Where memory.json lives — injectable so tests can use a scratch directory.
    @ObservationIgnored private let storeDirectory: URL

    // MARK: - State

    private(set) var learnings: [Learning] = []

    /// Error sink wired by the app shell: (localization key, %@ detail).
    @ObservationIgnored var onError: ((String, String) -> Void)?
    /// A corrupt-load error parked until the app shell can show it (load() runs before
    /// any banner surface exists).
    var loadError: (key: String, detail: String)?

    init(storeDirectory: URL = AppPaths.supportDirectory()) {
        self.storeDirectory = storeDirectory
        load()
    }

    // MARK: - CRUD

    /// Add a learning, collapsing an existing one with the same dedupeKey (keeps the
    /// earliest createdAt + the higher timesApplied + OR-ed pinned). Returns the id of
    /// the stored (possibly pre-existing) learning.
    @discardableResult
    func add(_ learning: Learning) -> Learning.ID {
        if let i = learnings.firstIndex(where: { $0.dedupeKey == learning.dedupeKey }) {
            learnings[i].body = learning.body.isEmpty ? learnings[i].body : learning.body
            learnings[i].tags = Array(Set(learnings[i].tags + learning.tags)).sorted()
            learnings[i].pinned = learnings[i].pinned || learning.pinned
            learnings[i].timesApplied = max(learnings[i].timesApplied, learning.timesApplied)
            save()
            return learnings[i].id
        }
        learnings.insert(learning, at: 0)
        save()
        return learning.id
    }

    func update(_ learning: Learning) {
        guard let i = learnings.firstIndex(where: { $0.id == learning.id }) else { return }
        learnings[i] = learning
        save()
    }

    func delete(_ id: Learning.ID) {
        learnings.removeAll { $0.id == id }
        save()
    }

    func togglePinned(_ id: Learning.ID) {
        guard let i = learnings.firstIndex(where: { $0.id == id }) else { return }
        learnings[i].pinned.toggle()
        save()
    }

    /// Bump timesApplied after these learnings were injected into a generated file.
    func markApplied(ids: [Learning.ID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        for i in learnings.indices where set.contains(learnings[i].id) {
            learnings[i].timesApplied += 1
        }
        save()
    }

    // MARK: - Persistence (JSON in Application Support)

    /// Versioned wrapper with a tolerant decode, mirroring LoopStore.PersistedLoops.
    private struct Persisted: Codable {
        static let currentVersion = 1

        var schemaVersion: Int
        var learnings: [Learning]

        init(learnings: [Learning], schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.learnings = learnings
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, learnings }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            // Lossy per-element: one corrupt learning must not empty the whole base.
            if let all = try? c.decodeIfPresent([Learning].self, forKey: .learnings) {
                learnings = all ?? []
            } else if var u = try? c.nestedUnkeyedContainer(forKey: .learnings) {
                var out: [Learning] = []
                while !u.isAtEnd {
                    if let v = try? u.decode(Learning.self) { out.append(v) } else { _ = try? u.decode(DecoderSkip.self) }
                }
                learnings = out
            } else {
                learnings = []
            }
        }
    }

    private var storeURL: URL { storeDirectory.appendingPathComponent("memory.json") }

    func save() {
        let state = Persisted(learnings: learnings)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            onError?("banner.memorySaveFailed", error.localizedDescription)
        }
    }

    private func load() {
        let url = storeURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            // Preserve the unreadable file before the next save() overwrites it (same
            // corrupt-file backup behavior as LoopStore.load()).
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("memory-corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            loadError = ("banner.memoryCorrupt", backup.lastPathComponent)
            return
        }
        learnings = decoded.learnings
    }
}
