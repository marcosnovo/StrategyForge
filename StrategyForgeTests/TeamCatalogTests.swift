//
//  TeamCatalogTests.swift
//  StrategyForgeTests
//
//  Unit tests for the team catalog engine: the GitHub ref → raw URL parser and the
//  built-in starter-team resolution. Network fetch itself is not exercised here.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct TeamCatalogTests {

    // MARK: - Ref parser

    @Test func refWithHashPathBuildsRawURL() throws {
        let url = try TeamCatalogStore.rawURL(fromRef: "me/catalog#teams/backend.sfstrategy")
        #expect(url.absoluteString == "https://raw.githubusercontent.com/me/catalog/main/teams/backend.sfstrategy")
    }

    @Test func refHonorsExplicitRefAndStripsGitHubPrefix() throws {
        let url = try TeamCatalogStore.rawURL(fromRef: "https://github.com/me/catalog@dev#t/x.sfstrategy")
        #expect(url.absoluteString == "https://raw.githubusercontent.com/me/catalog/dev/t/x.sfstrategy")
    }

    @Test func refUsesThirdSegmentAsPathWhenNoHash() throws {
        let url = try TeamCatalogStore.rawURL(fromRef: "me/catalog/teams/x.sfstrategy")
        #expect(url.absoluteString == "https://raw.githubusercontent.com/me/catalog/main/teams/x.sfstrategy")
    }

    @Test func refWithoutPathIsRejected() {
        #expect(throws: (any Error).self) { try TeamCatalogStore.rawURL(fromRef: "me/catalog") }
    }

    @Test func refWithSingleTokenIsRejected() {
        #expect(throws: (any Error).self) { try TeamCatalogStore.rawURL(fromRef: "justme") }
    }

    // MARK: - Built-in starter teams

    @Test func everyKnownBuiltinKeyResolves() {
        let keys = ["orchestratorWorkers", "executorAdvisor", "scoutAct", "triageRouter",
                    "rootCauseDebugging", "plannerImplementersReviewer", "domainSpecialists",
                    "researchFanout", "debateConsensus", "sparring", "solo"]
        for key in keys {
            let s = TeamCatalogStore.builtinStrategy(key)
            #expect(s != nil, "\(key) should resolve")
            #expect(s?.orchestrator != nil, "\(key) should have an orchestrator")
        }
    }

    @Test func unknownBuiltinKeyReturnsNil() {
        #expect(TeamCatalogStore.builtinStrategy("nope") == nil)
    }

    @Test func everyCuratedBuiltinEntryResolves() {
        for entry in TeamCatalogStore.shared.curated {
            if case let .builtin(key) = entry.source {
                #expect(TeamCatalogStore.builtinStrategy(key) != nil,
                        "curated '\(entry.slug)' → missing built-in '\(key)'")
            }
        }
    }

    // MARK: - CuratedTeam URLs

    @Test func githubEntryBuildsStrategyURL() {
        let t = CuratedTeam(slug: "x", name: "X", description: "", category: "C",
                            source: .github(owner: "me", repo: "cat", ref: "main", path: "teams/x.sfstrategy"))
        #expect(t.strategyURL?.absoluteString == "https://raw.githubusercontent.com/me/cat/main/teams/x.sfstrategy")
        #expect(t.isRemote)
    }

    @Test func builtinEntryHasNoStrategyURLAndIsNotRemote() {
        let t = CuratedTeam(slug: "s", name: "Solo", description: "", category: "C", source: .builtin("solo"))
        #expect(t.strategyURL == nil)
        #expect(!t.isRemote)
    }
}
