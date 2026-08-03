//
//  TwoLevelMemoryTests.swift
//  StrategyForgeTests
//
//  The second memory level: `user` (how you like to work) vs `team` (a shared convention
//  that reads as POLICY). The parity gap the competitive analysis flagged against Factory's
//  User+Org memory.
//
//  What must hold:
//   • a team learning outranks a personal one, and survives a tight `limit`;
//   • the digest marks the level so the agent can tell binding from advisory;
//   • promoting a personal note to a team convention does NOT collapse into it;
//   • a base with no team entries behaves EXACTLY as it did before the level existed.
//

import Testing
import Foundation
@testable import Coral

struct TwoLevelMemoryTests {

    private func learning(_ title: String, scope: LearningScope = .user,
                          kind: LearningKind = .pattern, tags: [String] = [],
                          pinned: Bool = false, createdAt: Date = Date()) -> Learning {
        Learning(kind: kind, title: title, body: "\(title) detail.", tags: tags,
                 scope: scope, source: LearningSource(origin: .manual),
                 createdAt: createdAt, pinned: pinned)
    }

    private let anyContext = MemoryContext(repoPath: nil, language: nil, taskText: nil)

    // MARK: - Ranking

    @Test func aTeamConventionOutranksAPersonalPreference() {
        // The personal one is NEWER and has MORE tag overlap — it would win at one level.
        let ctx = MemoryContext(repoPath: nil, language: "swift", taskText: "refactor swift ui")
        let personal = learning("Prefer trailing closures", tags: ["swift", "ui"],
                                createdAt: Date(timeIntervalSince1970: 2_000))
        let team = learning("All PRs need a test", scope: .team,
                            createdAt: Date(timeIntervalSince1970: 1_000))
        let picked = MemorySelector.topN([personal, team], context: ctx, limit: 2)
        #expect(picked.map(\.title) == ["All PRs need a test", "Prefer trailing closures"])
    }

    @Test func aTightLimitDropsPreferencesBeforeConventions() {
        let team = (1...3).map { learning("team-\($0)", scope: .team) }
        let personal = (1...5).map { learning("me-\($0)") }
        let picked = MemorySelector.topN(personal + team, context: anyContext, limit: 3)
        #expect(picked.allSatisfy { $0.scope == .team })
        #expect(Set(picked.map(\.title)) == Set(["team-1", "team-2", "team-3"]))
    }

    @Test func personalLearningsStillFillTheRemainingSlots() {
        let team = [learning("shared rule", scope: .team)]
        let personal = (1...5).map { learning("me-\($0)") }
        let picked = MemorySelector.topN(team + personal, context: anyContext, limit: 4)
        #expect(picked.count == 4)
        #expect(picked.first?.scope == .team)
        #expect(picked.dropFirst().allSatisfy { $0.scope == .user })
    }

    @Test func aBaseWithNoTeamEntriesRanksExactlyAsItAlwaysDid() {
        // The regression guard for every install that upgrades into this feature.
        let old = learning("older", createdAt: Date(timeIntervalSince1970: 1_000))
        let new = learning("newer", createdAt: Date(timeIntervalSince1970: 5_000))
        let pin = learning("pinned", pinned: true, createdAt: Date(timeIntervalSince1970: 0))
        let picked = MemorySelector.topN([old, new, pin], context: anyContext, limit: 3)
        #expect(picked.map(\.title) == ["pinned", "newer", "older"])
    }

    @Test func repoScopingStillGatesBothLevels() {
        // A level is not an escape hatch from repo scoping: a team learning pinned to
        // another repo still must not leak into this one.
        var elsewhere = learning("only in other-repo", scope: .team)
        elsewhere.repoScope = "/Users/me/other-repo"
        let global = learning("everywhere", scope: .team)
        let ctx = MemoryContext(repoPath: "/Users/me/this-repo", language: nil, taskText: nil)
        let picked = MemorySelector.topN([elsewhere, global], context: ctx, limit: 5)
        #expect(picked.map(\.title) == ["everywhere"])
    }

    // MARK: - The digest the agent actually reads

    @Test func theDigestMarksTheTeamLevelAndExplainsIt() {
        let md = MemoryDigest.render([learning("All PRs need a test", scope: .team),
                                      learning("Prefer trailing closures")])
        #expect(md.contains("- [team] **All PRs need a test**"))
        #expect(md.contains("- **Prefer trailing closures**"))
        #expect(!md.contains("[team] **Prefer trailing closures**"))
        #expect(md.contains("treat them as binding"))
    }

    @Test func theDigestIsUnchangedWhenNothingIsSharedYet() {
        // Byte-identical to the pre-levels output for a purely personal base — the
        // generated CLAUDE.md must not churn on upgrade.
        let md = MemoryDigest.render([learning("Prefer trailing closures")])
        #expect(!md.contains("[team]"))
        #expect(!md.contains("binding"))
        #expect(md.contains("- **Prefer trailing closures** — Prefer trailing closures detail."))
    }

    // MARK: - Dedupe across the levels

    @Test func promotingAPreferenceToAConventionDoesNotCollapseIntoIt() {
        let personal = learning("Always run the gate")
        let shared = learning("Always run the gate", scope: .team)
        #expect(personal.dedupeKey != shared.dedupeKey)
    }

    @Test func twoEntriesAtTheSameLevelStillCollapse() {
        let a = learning("Always run the gate", scope: .team)
        let b = learning("  always RUN the gate  ", scope: .team)
        #expect(a.dedupeKey == b.dedupeKey)
    }

    @Test @MainActor func theStoreKeepsBothLevelsSideBySide() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mem-levels-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = MemoryStore(storeDirectory: dir)
        store.add(learning("Always run the gate"))
        store.add(learning("Always run the gate", scope: .team))
        #expect(store.learnings.count == 2)

        let reloaded = MemoryStore(storeDirectory: dir)
        #expect(reloaded.learnings.filter { $0.scope == .team }.count == 1)
        #expect(reloaded.learnings.filter { $0.scope == .user }.count == 1)
    }

    // MARK: - Persistence

    @Test func learningsSavedBeforeTheLevelsExistedAreYours() throws {
        let data = try JSONEncoder().encode(learning("legacy"))
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "scope")
        let legacy = try JSONDecoder().decode(
            Learning.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.scope == .user)

        // An unknown level from a newer build must not fail the decode of the whole base.
        json["scope"] = "org-wide-from-the-future"
        let future = try JSONDecoder().decode(
            Learning.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(future.scope == .user)
    }

    @Test func theLevelSurvivesARoundTrip() throws {
        let data = try JSONEncoder().encode(learning("shared", scope: .team))
        #expect(try JSONDecoder().decode(Learning.self, from: data).scope == .team)
    }
}
