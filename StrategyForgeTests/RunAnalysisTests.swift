//
//  RunAnalysisTests.swift
//  StrategyForgeTests
//
//  Unit tests for the run test-bench: re-tune suggestions from a single finished
//  run, and the two-run comparison diff. Pure, so no mocks are needed.
//

import Testing
import Foundation
@testable import Coral

struct RunAnalysisTests {

    // MARK: - Builders

    private func role(_ name: String, _ kind: RoleKind, orchestrator: Bool = false) -> AgentRole {
        AgentRole(name: name, role: kind, model: .sonnet5,
                  systemPrompt: "", description: "", isOrchestrator: orchestrator)
    }

    private func strategy(_ roles: [AgentRole]) -> Strategy {
        Strategy(name: "Test", description: "", roles: roles, orchestrationNotes: "")
    }

    private func step(_ title: String, agent: String? = nil, delegation: Bool = false) -> ActivityStep {
        ActivityStep(title: title, detail: nil, at: Date(timeIntervalSince1970: 0),
                     isDelegation: delegation, agent: agent)
    }

    private func turn(steps: [ActivityStep] = [],
                      agentsInvolved: [String] = [],
                      tokens: Int = 0, cost: Double = 0,
                      byModel: [ModelSpend] = [],
                      byAgent: [String: Int] = [:],
                      seconds: Double = 0) -> TurnActivity {
        TurnActivity(turnIndex: 0, prompt: "do it",
                     startedAt: Date(timeIntervalSince1970: 0),
                     endedAt: Date(timeIntervalSince1970: seconds),
                     steps: steps, agentsInvolved: agentsInvolved, commandLog: [],
                     tokensUsed: tokens, costUSD: cost, byModel: byModel, byAgent: byAgent)
    }

    // MARK: - Re-tune: idle agent

    @Test func idleAgentIsFlagged() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker), role("review", .reviewer)])
        // impl worked; review never showed up.
        let t = turn(steps: [step("edit", agent: "impl")],
                     agentsInvolved: ["impl"], tokens: 100, cost: 0.1,
                     byModel: [ModelSpend(model: "claude-sonnet-5", tokens: 100, costUSD: 0.1)],
                     byAgent: ["impl": 100])
        let suggestions = RunAnalysis.retune(turn: t, strategy: s)
        #expect(suggestions.contains { $0.kind == .idleAgent && $0.subject == "review" })
        #expect(!suggestions.contains { $0.kind == .idleAgent && $0.subject == "impl" })
    }

    // MARK: - Re-tune: no delegation

    @Test func noDelegationWhenTeamNeverSplit() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker)])
        let t = turn(steps: [step("read"), step("edit")],   // all orchestrator, no delegation
                     agentsInvolved: [], tokens: 500, cost: 0.2)
        let suggestions = RunAnalysis.retune(turn: t, strategy: s)
        #expect(suggestions.contains { $0.kind == .noDelegation })
    }

    @Test func soloTeamNeverTriggersDelegationOrIdle() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true)])
        let t = turn(steps: [step("answer")], tokens: 200, cost: 0.05,
                     byModel: [ModelSpend(model: "claude-opus-4-8", tokens: 200, costUSD: 0.05)])
        let suggestions = RunAnalysis.retune(turn: t, strategy: s)
        #expect(suggestions.isEmpty)
    }

    // MARK: - Re-tune: cost hog

    @Test func dominantModelIsFlaggedAsCostHog() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true), role("w", .worker)])
        let t = turn(steps: [step("x", agent: "w")], agentsInvolved: ["w"], tokens: 1000, cost: 0.4,
                     byModel: [ModelSpend(model: "claude-opus-4-8", tokens: 900, costUSD: 0.36),
                               ModelSpend(model: "claude-haiku-4-5", tokens: 100, costUSD: 0.04)],
                     byAgent: ["w": 1000])
        let suggestions = RunAnalysis.retune(turn: t, strategy: s)
        let hog = suggestions.first { $0.kind == .costHog }
        #expect(hog != nil)
        #expect(hog?.subject == "Opus 4.8")
        #expect(hog?.value == "90%")
    }

    @Test func balancedSpendIsNotACostHog() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true), role("w", .worker)])
        let t = turn(steps: [step("x", agent: "w")], agentsInvolved: ["w"], tokens: 1000, cost: 0.4,
                     byModel: [ModelSpend(model: "claude-opus-4-8", tokens: 500, costUSD: 0.2),
                               ModelSpend(model: "claude-sonnet-5", tokens: 500, costUSD: 0.2)],
                     byAgent: ["w": 1000])
        #expect(!RunAnalysis.retune(turn: t, strategy: s).contains { $0.kind == .costHog })
    }

    // MARK: - Re-tune: expensive run

    @Test func expensiveRunIsFlaggedWithFormattedCost() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true)])
        let t = turn(steps: [step("x")], tokens: 100_000, cost: 1.5,
                     byModel: [ModelSpend(model: "claude-opus-4-8", tokens: 100_000, costUSD: 1.5)])
        let s2 = RunAnalysis.retune(turn: t, strategy: s)
        let exp = s2.first { $0.kind == .expensiveRun }
        #expect(exp?.value == "$1.50")
    }

    @Test func suggestionsAreOrderedBySeverity() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true), role("impl", .worker)])
        // noDelegation (warning) + expensiveRun (info) both fire.
        let t = turn(steps: [step("read"), step("edit")], agentsInvolved: [], tokens: 100_000, cost: 2.0)
        let out = RunAnalysis.retune(turn: t, strategy: s)
        #expect(out.first?.kind == .noDelegation)   // warning sorts before info
    }

    // MARK: - Compare

    @Test func compareProducesSignedDeltas() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true), role("w", .worker)])
        let a = turn(steps: [step("x", agent: "w"), step("y", agent: "w")],
                     tokens: 1000, cost: 0.80, byAgent: ["w": 1000], seconds: 40)
        let b = turn(steps: [step("x", agent: "w")],
                     tokens: 600, cost: 0.30, byAgent: ["w": 600], seconds: 25)
        let d = RunAnalysis.compare(a, b, strategy: s)
        #expect(d.costDelta == -0.5)
        #expect(d.tokenDelta == -400)
        #expect(d.stepDelta == -1)
        #expect(d.secondsDelta == -15)
        #expect(d.costPercent != nil)
        // Union has the single agent "w".
        #expect(d.agents.map(\.name) == ["w"])
        #expect(d.agents.first?.tokensA == 1000)
        #expect(d.agents.first?.tokensB == 600)
        #expect(d.agents.first?.stepsA == 2)
        #expect(d.agents.first?.stepsB == 1)
    }

    @Test func compareUnionsAgentsAcrossBothRuns() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true)])
        let a = turn(byAgent: ["alpha": 100])
        let b = turn(byAgent: ["beta": 200])
        let d = RunAnalysis.compare(a, b, strategy: s)
        #expect(Set(d.agents.map(\.name)) == ["alpha", "beta"])
    }

    @Test func costPercentNilWhenBaselineHadNoCost() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true)])
        let d = RunAnalysis.compare(turn(cost: 0), turn(cost: 0.5), strategy: s)
        #expect(d.costPercent == nil)
    }
}
