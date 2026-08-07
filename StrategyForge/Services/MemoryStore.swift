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

    /// Audit trail (newest first, capped) — what was learned, approved, edited, forgotten, and
    /// when. Keeps the knowledge base observable so a wrong memory can be traced and rolled back.
    private(set) var auditLog: [MemoryEvent] = []
    private static let auditCap = 300

    private func audit(_ action: MemoryEvent.Action, _ title: String) {
        auditLog.insert(MemoryEvent(action: action, title: title, at: Date()), at: 0)
        if auditLog.count > Self.auditCap { auditLog.removeLast(auditLog.count - Self.auditCap) }
    }

    /// Error sink wired by the app shell: (localization key, %@ detail).
    @ObservationIgnored var onError: ((String, String) -> Void)?
    /// A corrupt-load error parked until the app shell can show it (load() runs before
    /// any banner surface exists).
    var loadError: (key: String, detail: String)?

    /// Cross-device sync backend. Defaults to LocalOnly (a no-op) so the base is
    /// device-local until CloudKit is wired + verified; swap in CloudKitLearningSync to
    /// enable roaming. Injectable for tests.
    @ObservationIgnored var syncStore: LearningSyncStore = LocalOnlyLearningSync()

    init(storeDirectory: URL = AppPaths.supportDirectory(),
         syncStore: LearningSyncStore = LocalOnlyLearningSync()) {
        self.storeDirectory = storeDirectory
        self.syncStore = syncStore
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
            learnings[i].updatedAt = learning.updatedAt          // touch so sync sees the merge
            save()
            return learnings[i].id
        }
        learnings.insert(learning, at: 0)
        audit(.added, learning.title)
        save()
        return learning.id
    }

    func update(_ learning: Learning) {
        guard let i = learnings.firstIndex(where: { $0.id == learning.id }) else { return }
        var edited = learning
        edited.updatedAt = Date()                                // stamp for last-writer-wins
        learnings[i] = edited
        audit(.edited, edited.title)
        save()
    }

    func delete(_ id: Learning.ID) {
        delete(id, forgotten: false)
    }

    /// Delete a learning. `forgotten: true` marks it in the audit trail as a deliberate
    /// "forget" (staleness sweep) rather than a plain manual delete.
    func delete(_ id: Learning.ID, forgotten: Bool) {
        guard let l = learnings.first(where: { $0.id == id }) else { return }
        learnings.removeAll { $0.id == id }
        audit(forgotten ? .forgotten : .deleted, l.title)
        save()
    }

    func togglePinned(_ id: Learning.ID) {
        guard let i = learnings.firstIndex(where: { $0.id == id }) else { return }
        learnings[i].pinned.toggle()
        learnings[i].updatedAt = Date()
        audit(learnings[i].pinned ? .pinned : .unpinned, learnings[i].title)
        save()
    }

    /// Promote a pending (auto-harvested) learning to canonical — the human gatekeeping step
    /// that lets it be injected into agents. Only after this does the knowledge become "truth".
    func approve(_ id: Learning.ID) {
        guard let i = learnings.firstIndex(where: { $0.id == id }), !learnings[i].reviewed else { return }
        learnings[i].reviewed = true
        learnings[i].updatedAt = Date()
        audit(.approved, learnings[i].title)
        save()
    }

    /// Auto-harvested learnings still awaiting human review (not yet canonical).
    var pendingReviewCount: Int { learnings.filter { !$0.reviewed && !$0.pinned }.count }

    /// Bump timesApplied after these learnings were injected into a generated file.
    func markApplied(ids: [Learning.ID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        let now = Date()
        for i in learnings.indices where set.contains(learnings[i].id) {
            learnings[i].timesApplied += 1
            learnings[i].lastAppliedAt = now   // refresh relevance → resets staleness
        }
        save()
    }

    // MARK: - Hygiene (forgetting + contradictions)

    /// Stale learnings (old + long unused, never pinned) — surfaced for a keep-or-forget review.
    func staleLearnings(now: Date = Date()) -> [Learning] { MemoryHygiene.staleLearnings(learnings, now: now) }
    /// Conflicting pairs (same subject + scope, divergent guidance) — surfaced, never auto-merged.
    var conflicts: [MemoryConflict] { MemoryHygiene.conflicts(learnings) }
    func learning(_ id: Learning.ID) -> Learning? { learnings.first { $0.id == id } }

    // MARK: - Digest + reflection

    /// The relevant-learnings markdown block for a run's context (repo + task), ready to
    /// inject into a generated CLAUDE.md / LOOP.md. Empty when nothing applies.
    func digest(repoPath: String?, task: String?, limit: Int = 6) -> String {
        // Only CANONICAL knowledge is injected into agents: reviewed (or pinned) entries. A
        // pending auto-harvested lesson could be wrong; injecting it would compound the error
        // across every run (Replit's "operational truth layer" — enter through review).
        let canonical = learnings.filter { $0.reviewed || $0.pinned }
        let picked = MemorySelector.topN(
            canonical, context: MemoryContext(repoPath: repoPath, language: nil, taskText: task), limit: limit)
        return MemoryDigest.render(picked)
    }

    /// Post-run reflection: harvest a loop's STATE.md into the global base. Honest — the
    /// STATE.md is written by the loop and its independent verifier, not fabricated; dedupe
    /// collapses repeats across runs. Returns the number of net-new learnings added.
    @discardableResult
    func harvestStateFile(at repoURL: URL) -> Int {
        let url = repoURL.appendingPathComponent("STATE.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let before = learnings.count
        for l in StateFileParser.learnings(fromStateMd: text, repo: repoURL.path) { add(l) }
        return learnings.count - before
    }

    // MARK: - Cross-device sync (opt-in; no-op until CloudKit is enabled)

    /// Pull remote learnings, last-writer-wins merge them in, then push the reconciled
    /// set back. Best-effort and a no-op when sync is unavailable (offline / signed-out /
    /// LocalOnly). The merge is pure (LearningMerge) and unit-tested.
    func syncNow() async {
        guard await syncStore.isAvailable else { return }
        do {
            let remote = try await syncStore.pull()
            let merged = LearningMerge.merge(local: learnings, remote: remote)
            if merged != learnings { learnings = merged; save() }
            try await syncStore.push(learnings)
        } catch {
            onError?("banner.memorySaveFailed", error.localizedDescription)
        }
    }

    // MARK: - Persistence (JSON in Application Support)

    /// Versioned wrapper with a tolerant decode, mirroring LoopStore.PersistedLoops.
    private struct Persisted: Codable {
        static let currentVersion = 1

        var schemaVersion: Int
        var learnings: [Learning]
        var auditLog: [MemoryEvent]

        init(learnings: [Learning], auditLog: [MemoryEvent] = [], schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.learnings = learnings
            self.auditLog = auditLog
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, learnings, auditLog }

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
            auditLog = (try? c.decodeIfPresent([MemoryEvent].self, forKey: .auditLog)) ?? []
        }
    }

    private var storeURL: URL { storeDirectory.appendingPathComponent("memory.json") }

    func save() {
        let state = Persisted(learnings: learnings, auditLog: auditLog)
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
        auditLog = decoded.auditLog
    }
}
