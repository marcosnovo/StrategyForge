//
//  EditProvenanceTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for per-file authorship: resolving an active-subagent name to the
//  responsible team member (its pinned model/provider), the orchestrator fallback, and
//  the compact badge label.
//

import Testing
import Foundation
@testable import Coral

struct EditProvenanceTests {

    private func strategy() -> Strategy {
        let orch = AgentRole(name: "lead", role: .orchestrator, model: .opus48,
                             systemPrompt: "", description: "", isOrchestrator: true)
        let reviewer = AgentRole(name: "reviewer", role: .worker, model: .sonnet5,
                                 provider: .gemini, providerModelID: nil,
                                 systemPrompt: "", description: "")
        let coder = AgentRole(name: "coder", role: .worker, model: .haiku45,
                              systemPrompt: "", description: "")
        return Strategy(name: "T", description: "", roles: [orch, reviewer, coder], orchestrationNotes: "")
    }

    @Test func noSubagentCreditsTheOrchestrator() {
        let p = EditProvenanceResolver.attribute(subagent: nil, strategy: strategy())
        #expect(p.agent == nil)
        #expect(p.provider == .claude)                 // orchestrator "lead" is a Claude role
        #expect(p.label(orchestratorName: "lead") == "lead · \(ClaudeModel.opus48.displayName)")
    }

    @Test func matchedSubagentCreditsItsPinnedModelAndProvider() {
        let p = EditProvenanceResolver.attribute(subagent: "reviewer", strategy: strategy())
        #expect(p.agent == "reviewer")
        #expect(p.provider == .gemini)                 // the role's provider, not the orchestrator's
        #expect(p.label(orchestratorName: "lead").hasPrefix("reviewer · "))
    }

    @Test func subagentMatchIsLooseOnTitleForm() {
        // The CLI may report a display-form name ("Reviewer"); it still resolves.
        let p = EditProvenanceResolver.attribute(subagent: "Reviewer", strategy: strategy())
        #expect(p.agent == "reviewer")
        #expect(p.provider == .gemini)
    }

    @Test func unknownSubagentIsCreditedByNameWithUnknownModel() {
        let p = EditProvenanceResolver.attribute(subagent: "ghost", strategy: strategy())
        #expect(p.agent == "ghost")
        #expect(p.model.isEmpty)                        // no matching role → model unknown
        // Label still reads the agent name, with no trailing " · ".
        #expect(p.label(orchestratorName: "lead") == "ghost")
    }

    @Test func blankSubagentFallsBackToOrchestrator() {
        let p = EditProvenanceResolver.attribute(subagent: "   ", strategy: strategy())
        #expect(p.agent == nil)
        #expect(p.label(orchestratorName: "lead").contains("lead"))
    }
}

struct LineAttributorTests {

    private let alice = EditProvenance(agent: "alice", model: "Sonnet 5", provider: .claude)
    private let bob = EditProvenance(agent: "bob", model: "Gemini", provider: .gemini)

    @Test func firstEditCreditsEveryLineToTheAuthor() {
        let out = LineAttributor.attribute(old: [], oldAuthors: [],
                                           new: ["a", "b", "c"], author: alice)
        #expect(out == [alice, alice, alice])
    }

    @Test func emptyNewYieldsEmpty() {
        #expect(LineAttributor.attribute(old: ["x"], oldAuthors: [alice], new: [], author: bob).isEmpty)
    }

    @Test func insertedLinesGetTheNewAuthorUnchangedKeepTheirs() {
        // alice wrote ["a","b","c"]; bob inserts "b2" between b and c.
        let out = LineAttributor.attribute(
            old: ["a", "b", "c"], oldAuthors: [alice, alice, alice],
            new: ["a", "b", "b2", "c"], author: bob)
        #expect(out == [alice, alice, bob, alice])
    }

    @Test func replacedLineIsCreditedToTheEditorOnlyOnThatLine() {
        // alice wrote 3 lines; bob changes the middle one.
        let out = LineAttributor.attribute(
            old: ["a", "b", "c"], oldAuthors: [alice, alice, alice],
            new: ["a", "B!", "c"], author: bob)
        #expect(out == [alice, bob, alice])
    }

    @Test func deletedLinesLeaveRemainingAuthorshipIntact() {
        // alice wrote 3 lines; bob deletes the middle one — no line is credited to bob.
        let out = LineAttributor.attribute(
            old: ["a", "b", "c"], oldAuthors: [alice, alice, alice],
            new: ["a", "c"], author: bob)
        #expect(out == [alice, alice])
    }

    @Test func appendedLinesAtEndGetTheEditor() {
        let out = LineAttributor.attribute(
            old: ["a"], oldAuthors: [alice],
            new: ["a", "b", "c"], author: bob)
        #expect(out == [alice, bob, bob])
    }

    @Test func oversizeDiffFallsBackToAllAuthorWithoutAligning() {
        // Beyond the LCS guard, everything is credited to the current editor (bounded work).
        let big = Array(repeating: "x", count: 1500)
        let out = LineAttributor.attribute(old: big, oldAuthors: Array(repeating: alice, count: 1500),
                                           new: big, author: bob)
        #expect(out.count == 1500)
        #expect(out.allSatisfy { $0 == bob })   // 1500*1500 = 2.25M > maxPairs → no alignment
    }
}
