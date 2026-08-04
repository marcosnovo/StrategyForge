//
//  TeamImproverTests.swift
//  StrategyForgeTests
//
//  The recursive auto-improvement (RAI) engine: pure edit parse/apply, and the full
//  convergent loop driven by a mock runner (no CLIs). Proves the loop pulls a team toward
//  its spec — a failing probe becomes passing after the editor tightens the system prompt.
//

import Testing
import Foundation
@testable import Coral

private func soloTeam(systemPrompt: String = "") -> Strategy {
    let orch = AgentRole(name: "orchestrator", role: .orchestrator, model: .opus48,
                         systemPrompt: systemPrompt, description: "Lead", count: 1, isOrchestrator: true)
    return Strategy(name: "Helper", description: "Answers questions", roles: [orch], orchestrationNotes: "")
}

struct TeamImproverPureTests {
    @Test func parseEditResolvesRoleAndCapturesBefore() {
        let team = soloTeam(systemPrompt: "old prompt")
        let json = #"{"role":"orchestrator","field":"systemPrompt","value":"new prompt","rationale":"tighten"}"#
        let edit = TeamImprover.parseEdit(json, team: team)
        #expect(edit?.roleName == "orchestrator")
        #expect(edit?.field == .systemPrompt)
        #expect(edit?.before == "old prompt")
        #expect(edit?.after == "new prompt")
    }

    @Test func parseEditRejectsNoOpAndUnknownRole() {
        let team = soloTeam(systemPrompt: "same")
        // No-op (value equals current) → nil, never a wasted round.
        #expect(TeamImprover.parseEdit(#"{"role":"orchestrator","field":"systemPrompt","value":"same"}"#, team: team) == nil)
        // Unknown role → nil.
        #expect(TeamImprover.parseEdit(#"{"role":"ghost","field":"systemPrompt","value":"x"}"#, team: team) == nil)
        // Garbage → nil.
        #expect(TeamImprover.parseEdit("not json", team: team) == nil)
    }

    @Test func applyEditsTheRightField() {
        let team = soloTeam(systemPrompt: "a")
        let e = TeamEdit(roleName: "orchestrator", field: .systemPrompt, before: "a", after: "b", rationale: "")
        #expect(TeamImprover.apply(e, to: team).orchestrator?.systemPrompt == "b")
        // Claude model edit maps onto the ClaudeModel enum.
        let me = TeamEdit(roleName: "orchestrator", field: .model, before: "claude-opus-4-8", after: "claude-haiku-4-5", rationale: "")
        #expect(TeamImprover.apply(me, to: team).orchestrator?.model == .haiku45)
        // apply never mutates the input.
        #expect(team.orchestrator?.systemPrompt == "a")
    }
}

/// One mock plays three roles by branching on the prompt text: team answer, judge, editor.
/// It answers "ZZZ" only once the orchestrator's system prompt carries the rule "SAY ZZZ",
/// the judge passes only when the answer contains ZZZ, and the editor adds that exact rule —
/// so a baseline of 0% must converge to 100% after one edit.
private final class ConvergingMock: OneShotRunner, @unchecked Sendable {
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        let text: String
        if prompt.contains("INDEPENDENT judge") {
            let pass = prompt.contains("ZZZ")   // the team's answer is embedded in the judge prompt
            text = "{\"pass\": \(pass), \"reason\": \"ok\"}"
        } else if prompt.contains("improving an AI agent team") {
            text = #"{"role":"orchestrator","field":"systemPrompt","value":"SAY ZZZ","rationale":"add the rule"}"#
        } else {
            text = prompt.contains("SAY ZZZ") ? "ZZZ" : "no"   // team answer depends on the system prompt
        }
        return OneShotResult(text: text, tokens: 1, costUSD: 0, provider: provider, model: model)
    }
}

@MainActor
struct TeamImproverLoopTests {
    @Test func convergesByEditingTheSystemPrompt() async {
        var team = soloTeam()   // empty system prompt → fails at first
        team.evalSuite = EvalSuite(scenarios: [
            EvalScenario(prompt: "Q", expectation: "answers well", category: .answersCorrectly)
        ], passThreshold: 1.0)
        let mock = ConvergingMock()
        let outcome = await TeamImprover.improve(team: team, usageExcerpts: [], maxIterations: 5,
                                                 answerRunner: mock, judgeRunner: mock) { _ in }
        #expect(outcome?.startPassRate == 0.0)          // baseline failed
        #expect(outcome?.endPassRate == 1.0)            // converged after editing the prompt
        #expect(outcome?.edits.count == 1)              // one lever changed
        #expect(outcome?.improvedTeam.orchestrator?.systemPrompt == "SAY ZZZ")
    }

    @Test func stopsWhenAlreadyPassing() async {
        var team = soloTeam(systemPrompt: "SAY ZZZ")   // already carries the rule → passes at baseline
        team.evalSuite = EvalSuite(scenarios: [
            EvalScenario(prompt: "Q", expectation: "answers well", category: .answersCorrectly)
        ], passThreshold: 1.0)
        let mock = ConvergingMock()
        let outcome = await TeamImprover.improve(team: team, usageExcerpts: [], maxIterations: 5,
                                                 answerRunner: mock, judgeRunner: mock) { _ in }
        #expect(outcome?.startPassRate == 1.0)
        #expect(outcome?.edits.isEmpty == true)   // nothing to fix → no edits
    }
}

struct UsageAwareGenerationTests {
    @Test func usagePromptIncludesRealExcerpts() {
        let team = soloTeam()
        let p = EvalRunner.generatePrompt(team: team, count: 5,
                                          usageExcerpts: ["how do I export the report?", "why did it skip step 2?"])
        #expect(p.contains("REAL USAGE"))
        #expect(p.contains("export the report"))
    }

    @Test func noUsageOmitsTheBlock() {
        let p = EvalRunner.generatePrompt(team: soloTeam(), count: 5)
        #expect(!p.contains("REAL USAGE"))
    }
}
