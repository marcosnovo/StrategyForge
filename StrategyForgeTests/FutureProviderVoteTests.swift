//
//  FutureProviderVoteTests.swift
//  StrategyForgeTests
//
//  The roadmap-vote store: toggling a vote is idempotent, persists across an AppModel
//  reload (via the same settings round-trip as provider plans), and old saved settings
//  that predate the votes key still decode (tolerant init).
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct FutureProviderVoteTests {

    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-votes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func toggleIsIdempotentAndReversible() {
        var s = AppSettings()
        #expect(!s.hasVotedFuture("kimi"))
        #expect(s.toggleFutureVote("kimi") == true)
        #expect(s.hasVotedFuture("kimi"))
        #expect(s.votedFutureProviders == ["kimi"])   // no duplicates
        #expect(s.toggleFutureVote("kimi") == false)
        #expect(!s.hasVotedFuture("kimi"))
        #expect(s.votedFutureProviders.isEmpty)
    }

    @Test func votesPersistThroughAnAppModelReload() throws {
        try withTempDir { dir in
            let model = AppModel(storeDirectory: dir)
            model.toggleFutureVote("glm")
            model.toggleFutureVote("qwen")
            #expect(model.futureVoteCount == 2)
            model.save(stamp: false, sync: true)

            let reloaded = AppModel(storeDirectory: dir)
            #expect(reloaded.hasVotedFuture("glm"))
            #expect(reloaded.hasVotedFuture("qwen"))
            #expect(!reloaded.hasVotedFuture("kimi"))
            #expect(reloaded.futureVoteCount == 2)
        }
    }

    @Test func requestsPersistThroughAnAppModelReload() throws {
        try withTempDir { dir in
            let model = AppModel(storeDirectory: dir)
            model.requestFutureProvider("  Cohere  ")     // trimmed
            model.requestFutureProvider("")               // ignored
            model.save(stamp: false, sync: true)

            let reloaded = AppModel(storeDirectory: dir)
            #expect(reloaded.settings.requestedProviders == ["Cohere"])
        }
    }

    @Test func settingsPredatingVotesKeyStillDecode() throws {
        // A settings blob saved before the roadmap keys existed must load with empty
        // defaults, not throw (tolerant decodeIfPresent).
        // Only a couple of the oldest keys — every newer key (incl. the vote store) is
        // decodeIfPresent, so their absence must default, not throw.
        let legacy = """
        {"claudeBinary":"claude","codexBinary":"codex","geminiBinary":"gemini"}
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.votedFutureProviders.isEmpty)
        #expect(decoded.requestedProviders.isEmpty)
    }

    @Test func ballotSlugsAreUniqueAndTaglinesResolve() {
        let ids = FutureProvider.all.map(\.id)
        #expect(Set(ids).count == ids.count)          // no dup vote keys
        for f in FutureProvider.all {
            // Each tagline key resolves to a non-key string in both languages.
            #expect(L10n.string(f.taglineKey, langCode: "en") != f.taglineKey)
            #expect(L10n.string(f.taglineKey, langCode: "es") != f.taglineKey)
        }
    }
}
