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
