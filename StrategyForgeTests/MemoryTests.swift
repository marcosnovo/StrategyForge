//
//  MemoryTests.swift
//  StrategyForgeTests
//
//  The cross-project knowledge base: store round-trip + tolerant/lossy decode + corrupt
//  backup + dedupe (MemoryStore), the STATE.md → learnings parser, the pure ranking
//  (MemorySelector), the markdown digest (MemoryDigest), and its injection into the
//  generated CLAUDE.md (ClaudeMdGenerator) — the last must stay byte-identical when no
//  learnings apply, so it can never regress an existing generation.
//

import Testing
import Foundation
@testable import Coral

/// A scriptable sync backend for exercising MemoryStore.syncNow without CloudKit.
private final class FakeLearningSync: LearningSyncStore, @unchecked Sendable {
    var available: Bool
    var remote: [Learning]
    var pushed: [Learning] = []
    init(available: Bool = true, remote: [Learning] = []) { self.available = available; self.remote = remote }
    var isAvailable: Bool { get async { available } }
    func push(_ learnings: [Learning]) async throws { pushed = learnings }
    func pull() async throws -> [Learning] { remote }
    func delete(ids: [UUID]) async throws {}
}

@MainActor
struct MemoryStoreTests {

    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mem-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func manual(_ kind: LearningKind, _ title: String, tags: [String] = [], pinned: Bool = false) -> Learning {
        Learning(kind: kind, title: title, tags: tags, source: LearningSource(origin: .manual), pinned: pinned)
    }

    @Test func pendingLearningsAreNotInjectedUntilApproved() throws {
        try withTempDir { dir in
            let store = MemoryStore(storeDirectory: dir)
            // An auto-harvested learning (reviewed:false) about a specific repo/topic.
            let harvested = Learning(kind: .mistake, title: "Do not regenerate fixtures",
                                     tags: ["swift"], repoScope: "/repo",
                                     source: LearningSource(origin: .stateFile), reviewed: false)
            let id = store.add(harvested)
            #expect(store.pendingReviewCount == 1)
            // Pending → excluded from the digest injected into agents.
            #expect(store.digest(repoPath: "/repo", task: "fixtures").isEmpty)
            // Approve (human gatekeeping) → now canonical and injectable.
            store.approve(id)
            #expect(store.pendingReviewCount == 0)
            #expect(store.digest(repoPath: "/repo", task: "fixtures").contains("regenerate fixtures"))
        }
    }

    @Test func roundTripsThroughDisk() throws {
        try withTempDir { dir in
            let store = MemoryStore(storeDirectory: dir)
            store.add(manual(.pattern, "Prefer async/await"))
            store.add(manual(.mistake, "Don't regenerate fixtures"))
            #expect(store.learnings.count == 2)

            let reloaded = MemoryStore(storeDirectory: dir)
            #expect(reloaded.learnings.count == 2)
            #expect(reloaded.learnings.contains { $0.title == "Prefer async/await" && $0.kind == .pattern })
        }
    }

    @Test func addDedupesByKindTitleScopeAndMergesTagsAndPin() throws {
        try withTempDir { dir in
            let store = MemoryStore(storeDirectory: dir)
            store.add(manual(.pattern, "Use CoralRow", tags: ["ui"]))
            store.add(manual(.pattern, "  use coralrow  ", tags: ["swift"], pinned: true)) // same dedupeKey (case+trim)
            #expect(store.learnings.count == 1)
            let l = store.learnings[0]
            #expect(l.pinned)                                  // OR-ed
            #expect(Set(l.tags) == ["ui", "swift"])            // merged
            // A different KIND with the same title is a distinct learning.
            store.add(manual(.mistake, "Use CoralRow"))
            #expect(store.learnings.count == 2)
        }
    }

    @Test func deleteAndTogglePinPersist() throws {
        try withTempDir { dir in
            let store = MemoryStore(storeDirectory: dir)
            let id = store.add(manual(.decision, "Cool reef neutrals"))
            store.togglePinned(id)
            #expect(store.learnings.first?.pinned == true)
            store.delete(id)
            #expect(store.learnings.isEmpty)
            #expect(MemoryStore(storeDirectory: dir).learnings.isEmpty)
        }
    }

    @Test func lossyDecodeSkipsOneBadElementAndDefaultsMissingVersion() throws {
        try withTempDir { dir in
            // schemaVersion absent (→0) and a non-object element in the array: the good
            // one survives, the junk is skipped — one corrupt entry never empties the base.
            let json = """
            {"learnings":[{"kind":"pattern","title":"Kept","source":{"origin":"manual"}}, 12345]}
            """
            try Data(json.utf8).write(to: dir.appendingPathComponent("memory.json"))
            let store = MemoryStore(storeDirectory: dir)
            #expect(store.learnings.count == 1)
            #expect(store.learnings.first?.title == "Kept")
            #expect(store.loadError == nil)                    // lossy, not corrupt
        }
    }

    @Test func harvestStateFileImportsLearningsAndDedupesOnRepeat() throws {
        try withTempDir { dir in
            // A loop's STATE.md sitting in the working dir, as a run would leave it.
            let stateMd = """
            # STATE.md — loop memory

            ## General rules
            - Never regenerate fixtures

            ## Lessons learned
            - The auth token expires after 1h
            """
            try Data(stateMd.utf8).write(to: dir.appendingPathComponent("STATE.md"))
            let store = MemoryStore(storeDirectory: dir)

            let added = store.harvestStateFile(at: dir)
            #expect(added == 2)
            #expect(store.learnings.contains { $0.kind == .pattern && $0.title == "Never regenerate fixtures" })
            #expect(store.learnings.contains { $0.kind == .mistake && $0.source.origin == .stateFile })

            // Harvesting the same STATE.md again adds nothing (dedupe).
            #expect(store.harvestStateFile(at: dir) == 0)
            #expect(store.learnings.count == 2)
        }
    }

    @Test func harvestMissingStateFileIsANoOp() throws {
        try withTempDir { dir in
            #expect(MemoryStore(storeDirectory: dir).harvestStateFile(at: dir) == 0)
        }
    }

    @Test func updateStampsANewerUpdatedAt() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mem-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemoryStore(storeDirectory: dir)
        let id = store.add(Learning(kind: .pattern, title: "x", source: .init(origin: .manual),
                                    createdAt: Date(timeIntervalSinceReferenceDate: 0),
                                    updatedAt: Date(timeIntervalSinceReferenceDate: 0)))
        var l = store.learnings.first { $0.id == id }!
        l.title = "x edited"
        store.update(l)
        #expect(store.learnings.first { $0.id == id }!.updatedAt > Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func syncPullsMergesInRemoteAndPushesReconciled() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mem-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = Learning(kind: .decision, title: "from another mac", source: .init(origin: .manual))
        let fake = FakeLearningSync(remote: [remote])
        let store = MemoryStore(storeDirectory: dir, syncStore: fake)
        store.add(manual(.pattern, "local one"))

        await store.syncNow()
        // The remote learning was merged in locally…
        #expect(store.learnings.contains { $0.title == "from another mac" })
        // …and the reconciled set (both) was pushed back.
        #expect(Set(fake.pushed.map(\.title)) == ["local one", "from another mac"])
    }

    @Test func syncIsANoOpWhenUnavailable() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mem-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeLearningSync(available: false, remote: [manual(.pattern, "should-not-appear")])
        let store = MemoryStore(storeDirectory: dir, syncStore: fake)
        await store.syncNow()
        #expect(store.learnings.isEmpty)
        #expect(fake.pushed.isEmpty)
    }

    @Test func unreadableStoreIsBackedUpNotFatal() throws {
        try withTempDir { dir in
            try Data("{ not json".utf8).write(to: dir.appendingPathComponent("memory.json"))
            let store = MemoryStore(storeDirectory: dir)
            #expect(store.learnings.isEmpty)
            #expect(store.loadError?.key == "banner.memoryCorrupt")
            let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix("memory-corrupt-") }
            #expect(backups.count == 1)
        }
    }
}

struct MemoryLogicTests {

    // MARK: StateFileParser

    private static let sampleStateMd = """
    # STATE.md — loop memory

    <!-- The loop reads this file at the start of every run. -->

    ## Verified facts

    <!-- Things proven true. -->
    - Tests live in StrategyForgeTests

    ## General rules

    - Never regenerate fixtures
    - Keep the verifier read-only

    ## Open failures (investigate next session)

    ## Lessons learned

    A flaky timer test needs a long timeout on CI.

    ## Last session

    Ran the suite and it passed.
    """

    @Test func stateParserMapsHeadingsToKindsAndSkipsCommentsAndNarrative() {
        let ls = StateFileParser.learnings(fromStateMd: Self.sampleStateMd, repo: "/Users/x/MyRepo")
        // General rules → 2 patterns; Verified facts → 1 decision; Lessons learned → 1 mistake.
        #expect(ls.filter { $0.kind == .pattern }.count == 2)
        #expect(ls.filter { $0.kind == .decision }.count == 1)
        #expect(ls.filter { $0.kind == .mistake }.count == 1)
        // "Last session" narrative + empty "Open failures" contribute nothing.
        #expect(ls.count == 4)
        // Every parsed learning is tagged + scoped to the repo, with honest provenance.
        #expect(ls.allSatisfy { $0.repoScope == "/Users/x/MyRepo" && $0.tags.contains("myrepo") })
        #expect(ls.allSatisfy { $0.source.origin == .stateFile })
    }

    @Test func stateParserIgnoresEmptyDocument() {
        #expect(StateFileParser.learnings(fromStateMd: "# STATE.md\n\n## General rules\n\n<!-- only a comment -->",
                                          repo: "r").isEmpty)
    }

    // MARK: MemorySelector

    private func l(_ kind: LearningKind, _ title: String, tags: [String] = [], repo: String? = nil,
                   pinned: Bool = false, at t: TimeInterval = 0) -> Learning {
        Learning(kind: kind, title: title, tags: tags, repoScope: repo,
                 source: LearningSource(origin: .manual),
                 createdAt: Date(timeIntervalSinceReferenceDate: t), pinned: pinned)
    }

    @Test func selectorPutsPinnedFirstThenTagOverlapThenRecency() {
        let all = [
            l(.pattern, "old-generic", at: 100),
            l(.pattern, "swift-match", tags: ["swift"], at: 50),
            l(.pattern, "pinned-irrelevant", pinned: true, at: 10),
            l(.pattern, "new-generic", at: 200),
        ]
        let ctx = MemoryContext(repoPath: nil, language: "swift", taskText: nil)
        let top = MemorySelector.topN(all, context: ctx, limit: 3).map(\.title)
        #expect(top.first == "pinned-irrelevant")             // pinned always first
        #expect(top[1] == "swift-match")                      // then tag overlap
        #expect(top[2] == "new-generic")                      // then recency
        #expect(top.count == 3)                               // limit respected
    }

    @Test func selectorScopesRepoLearningsToTheirRepo() {
        let all = [
            l(.pattern, "global"),
            l(.pattern, "repoA-only", repo: "/x/RepoA"),
            l(.pattern, "repoB-only", repo: "/x/RepoB"),
        ]
        let inA = MemorySelector.topN(all, context: MemoryContext(repoPath: "/x/RepoA"), limit: 9).map(\.title)
        #expect(inA.contains("global"))
        #expect(inA.contains("repoA-only"))
        #expect(!inA.contains("repoB-only"))                  // other repo's learning excluded
    }

    // MARK: LearningMerge (cross-device, last-writer-wins)

    @Test func mergeAdoptsRemoteOnlyAndPrefersNewer() {
        let id = UUID()
        let localEdit = Learning(id: id, kind: .pattern, title: "local",
                                 source: .init(origin: .manual),
                                 createdAt: Date(timeIntervalSinceReferenceDate: 0),
                                 updatedAt: Date(timeIntervalSinceReferenceDate: 100))
        let remoteNewer = Learning(id: id, kind: .pattern, title: "remote",
                                   source: .init(origin: .manual),
                                   updatedAt: Date(timeIntervalSinceReferenceDate: 200))
        let remoteOnly = Learning(kind: .mistake, title: "only-remote", source: .init(origin: .manual))

        let merged = LearningMerge.merge(local: [localEdit], remote: [remoteNewer, remoteOnly])
        #expect(merged.count == 2)
        #expect(merged.first { $0.id == id }?.title == "remote")   // newer remote wins
        #expect(merged.contains { $0.title == "only-remote" })     // remote-only adopted

        // When local is newer, it stays.
        let localWins = LearningMerge.merge(
            local: [localEdit],
            remote: [Learning(id: id, kind: .pattern, title: "stale-remote", source: .init(origin: .manual),
                              updatedAt: Date(timeIntervalSinceReferenceDate: 50))])
        #expect(localWins.first { $0.id == id }?.title == "local")
    }

    // MARK: MemoryDigest

    @Test func digestEmptyForNoLearnings() {
        #expect(MemoryDigest.render([]).isEmpty)
    }

    @Test func digestGroupsByKindWithTitlesAndBodies() {
        let out = MemoryDigest.render([
            Learning(kind: .pattern, title: "Prefer async", body: "over Combine", source: LearningSource(origin: .manual)),
            Learning(kind: .mistake, title: "No force unwrap", source: LearningSource(origin: .manual)),
        ])
        #expect(out.contains("### Patterns that worked"))
        #expect(out.contains("- **Prefer async** — over Combine"))
        #expect(out.contains("### Pitfalls to avoid"))
        #expect(out.contains("- **No force unwrap**"))
    }
}

@MainActor
struct MemoryHygieneTests {

    private func learning(_ title: String, kind: LearningKind = .pattern, scope: String? = nil,
                          created: Date, applied: Date? = nil, pinned: Bool = false, body: String = "b") -> Learning {
        Learning(kind: kind, title: title, body: body, repoScope: scope,
                 source: LearningSource(origin: .manual), createdAt: created,
                 lastAppliedAt: applied, pinned: pinned)
    }

    @Test func stalenessTiersOnAgeAndDisuse() {
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)
        let fresh = learning("a", created: now.addingTimeInterval(-10 * 86_400))
        let aging = learning("b", created: now.addingTimeInterval(-70 * 86_400))
        let stale = learning("c", created: now.addingTimeInterval(-200 * 86_400))
        #expect(MemoryHygiene.staleness(fresh, now: now) == .fresh)
        #expect(MemoryHygiene.staleness(aging, now: now) == .aging)
        #expect(MemoryHygiene.staleness(stale, now: now) == .stale)
    }

    @Test func recentApplyResetsStaleness() {
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)
        // Old creation, but applied yesterday → fresh (still relevant).
        let l = learning("x", created: now.addingTimeInterval(-300 * 86_400),
                         applied: now.addingTimeInterval(-1 * 86_400))
        #expect(MemoryHygiene.staleness(l, now: now) == .fresh)
    }

    @Test func pinnedNeverGoesStale() {
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)
        let l = learning("x", created: now.addingTimeInterval(-999 * 86_400), pinned: true)
        #expect(MemoryHygiene.staleness(l, now: now) == .fresh)
    }

    @Test func conflictsSurfaceDivergentGuidanceOnSameSubject() {
        let now = Date()
        // Same subject + scope, DIFFERENT kind (pattern vs mistake) → conflict.
        let a = learning("Deploy via CI", kind: .pattern, scope: "repoA", created: now, body: "always CI")
        let b = learning("Deploy via CI", kind: .mistake, scope: "repoA", created: now, body: "CI is flaky")
        let conflicts = MemoryHygiene.conflicts([a, b])
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.subject == "Deploy via CI")
    }

    @Test func noConflictAcrossDifferentScopesOrSubjects() {
        let now = Date()
        let a = learning("Deploy via CI", kind: .pattern, scope: "repoA", created: now)
        let b = learning("Deploy via CI", kind: .mistake, scope: "repoB", created: now)  // different scope
        let c = learning("Use tabs", kind: .pattern, scope: "repoA", created: now)       // different subject
        #expect(MemoryHygiene.conflicts([a, b, c]).isEmpty)
    }
}

@MainActor
struct MemoryAuditTests {

    private func freshStore() -> MemoryStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return MemoryStore(storeDirectory: dir)
    }

    @Test func auditTrailRecordsAddApproveForget() {
        let store = freshStore()
        let id = store.add(Learning(kind: .pattern, title: "T", source: LearningSource(origin: .review), reviewed: false))
        store.approve(id)
        store.delete(id, forgotten: true)
        let actions = store.auditLog.map(\.action)
        #expect(actions.contains(.added))
        #expect(actions.contains(.approved))
        #expect(actions.contains(.forgotten))
        // Newest first.
        #expect(store.auditLog.first?.action == .forgotten)
    }

    @Test func markAppliedRefreshesLastApplied() {
        let store = freshStore()
        let id = store.add(Learning(kind: .pattern, title: "T", source: LearningSource(origin: .manual)))
        #expect(store.learning(id)?.lastAppliedAt == nil)
        store.markApplied(ids: [id])
        #expect(store.learning(id)?.lastAppliedAt != nil)
    }
}
