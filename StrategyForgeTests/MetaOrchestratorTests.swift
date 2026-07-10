//
//  MetaOrchestratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the Level 2 cross-provider engine: pure plan parsing / model
//  resolution, and the full Plan → Delegate → Synthesize loop driven by a mock
//  runner (so no CLIs are spawned).
//

import Testing
import Foundation
@testable import StrategyForge

/// Records every call and returns canned text based on the prompt kind.
private final class MockRunner: OneShotRunner, @unchecked Sendable {
    struct Call: Equatable { let provider: AIProvider; let model: String }
    private(set) var calls: [Call] = []
    var planJSON = "[]"

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        calls.append(Call(provider: provider, model: model))
        let text: String
        if prompt.contains("JSON array") { text = planJSON }
        else if prompt.contains("Combine your agents") { text = "FINAL ANSWER" }
        else { text = "result:\(model)" }
        return OneShotResult(text: text, tokens: 10, costUSD: 0.01, provider: provider, model: model)
    }
}

private final class EventBox: @unchecked Sendable {
    var events: [MetaEvent] = []
}

private func makeStrategy() -> Strategy {
    let orch = AgentRole(name: "orchestrator", role: .orchestrator, model: .opus48,
                         systemPrompt: "", description: "Lead", count: 1, isOrchestrator: true)
    let researcher = AgentRole(name: "researcher", role: .researcher, model: .sonnet5,
                               provider: .claude, systemPrompt: "", description: "Investigate", count: 1)
    var writer = AgentRole(name: "writer", role: .worker, model: .haiku45,
                           systemPrompt: "", description: "Write", count: 1)
    writer.provider = .gemini
    writer.providerModelID = "gemini-flash"
    return Strategy(name: "Test", description: "", roles: [orch, researcher, writer], orchestrationNotes: "")
}

struct MetaOrchestratorPureTests {
    @Test func resolvesModelIdPerProvider() {
        let claude = AgentRole(name: "a", role: .worker, model: .sonnet5, systemPrompt: "", description: "")
        #expect(MetaOrchestrator.modelID(for: claude) == "claude-sonnet-5")
        var gem = claude; gem.provider = .gemini; gem.providerModelID = "gemini-pro"
        #expect(MetaOrchestrator.modelID(for: gem) == "gemini-pro")
    }

    @Test func parsesPlanJSON() {
        let s = makeStrategy()
        let plan = MetaOrchestrator.parsePlan(
            #"Sure! [{"role":"researcher","task":"look into X"},{"role":"writer","task":"draft Y"}]"#,
            workers: s.subagentRoles, task: "T")
        #expect(plan == [.init(roleName: "researcher", task: "look into X"),
                         .init(roleName: "writer", task: "draft Y")])
    }

    @Test func planFallsBackWhenUnparseable() {
        let s = makeStrategy()
        let plan = MetaOrchestrator.parsePlan("no json here", workers: s.subagentRoles, task: "the task")
        // One subtask per worker, each carrying the whole task.
        #expect(plan.count == 2)
        #expect(plan.allSatisfy { $0.task == "the task" })
    }
}

struct MetaOrchestratorRunTests {
    @Test func runsPlanDelegateSynthesizeAcrossProviders() async {
        let strategy = makeStrategy()
        let runner = MockRunner()
        runner.planJSON = #"[{"role":"researcher","task":"research it"},{"role":"writer","task":"write it"}]"#
        let box = EventBox()

        let final = await MetaOrchestrator.run(strategy: strategy, task: "Do the thing", cwd: nil,
                                               runner: runner) { box.events.append($0) }

        // Final synthesized answer.
        #expect(final == "FINAL ANSWER")
        #expect(box.events.contains(.assistantText("FINAL ANSWER")))
        #expect(box.events.contains(.finished))

        // Four calls: plan(orch) → researcher → writer → synth(orch).
        #expect(runner.calls == [
            .init(provider: .claude, model: "claude-opus-4-8"),   // plan
            .init(provider: .claude, model: "claude-sonnet-5"),   // researcher
            .init(provider: .gemini, model: "gemini-flash"),      // writer (different provider!)
            .init(provider: .claude, model: "claude-opus-4-8"),   // synthesize
        ])

        // Usage is summed across all four calls.
        #expect(box.events.contains(.usage(tokens: 40, costUSD: 0.04)))
        // Phases were announced in order.
        let phases = box.events.compactMap { if case .phase(let p) = $0 { return p } else { return nil } }
        #expect(phases == ["plan", "delegate", "synthesize"])
    }

    @Test func soloTeamAnswersDirectly() async {
        let orch = AgentRole(name: "solo", role: .orchestrator, model: .opus48,
                             systemPrompt: "", description: "", count: 1, isOrchestrator: true)
        let strategy = Strategy(name: "Solo", description: "", roles: [orch], orchestrationNotes: "")
        let runner = MockRunner()
        let box = EventBox()
        let final = await MetaOrchestrator.run(strategy: strategy, task: "Just answer", cwd: nil,
                                               runner: runner) { box.events.append($0) }
        #expect(final == "result:claude-opus-4-8")
        #expect(runner.calls.count == 1)   // no plan/synthesize, just one answer
    }
}
