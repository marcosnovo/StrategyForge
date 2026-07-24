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
