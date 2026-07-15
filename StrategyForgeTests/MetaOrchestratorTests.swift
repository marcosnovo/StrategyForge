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
@testable import Coral

/// Records every call and returns canned text based on the prompt kind. Thread-safe
/// because delegated workers now run concurrently.
private final class MockRunner: OneShotRunner, @unchecked Sendable {
    struct Call: Equatable { let provider: AIProvider; let model: String }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    var planJSON = "[]"

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        lock.lock(); _calls.append(Call(provider: provider, model: model)); lock.unlock()
        let text: String
        if prompt.contains("JSON array") { text = planJSON }
        else if prompt.contains("Combine your agents") { text = "FINAL ANSWER" }
        else { text = "result:\(model)" }
        return OneShotResult(text: text, tokens: 10, costUSD: 0.01, provider: provider, model: model)
    }
}

/// Thread-safe event collector: `MetaOrchestrator.run` invokes `onEvent` from
/// CONCURRENT worker tasks (the delegate phase runs a task group), so appends must be
/// locked — an unsynchronized `Array.append` from parallel tasks corrupts the buffer
/// and crashes (EXC_BAD_ACCESS). Mirrors `MockRunner`'s locking.
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [MetaEvent] = []
    func append(_ event: MetaEvent) { lock.lock(); _events.append(event); lock.unlock() }
    var events: [MetaEvent] { lock.lock(); defer { lock.unlock() }; return _events }
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
                                               runner: runner) { box.append($0) }

        // Final synthesized answer.
        #expect(final == "FINAL ANSWER")
        #expect(box.events.contains(.assistantText("FINAL ANSWER")))
        #expect(box.events.contains(.finished))

        // Four calls total; workers run concurrently so their order isn't fixed.
        let calls = runner.calls
        #expect(calls.count == 4)
        // Orchestrator (plan + synthesize) ran twice on Opus.
        #expect(calls.filter { $0 == .init(provider: .claude, model: "claude-opus-4-8") }.count == 2)
        // The researcher ran on Claude Sonnet, the writer on a DIFFERENT provider (Gemini).
        #expect(calls.contains(.init(provider: .claude, model: "claude-sonnet-5")))
        #expect(calls.contains(.init(provider: .gemini, model: "gemini-flash")))

        // Usage is emitted as a per-step DELTA (so the live counter climbs during the
        // run, not just at the end) — one event per call, summing to the total.
        let usageDeltas = box.events.compactMap { if case .usage(let t, let c) = $0 { return (t, c) } else { return nil } }
        #expect(usageDeltas.count == 4)
        #expect(usageDeltas.reduce(0) { $0 + $1.0 } == 40)
        #expect(abs(usageDeltas.reduce(0.0) { $0 + $1.1 } - 0.04) < 0.0001)
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
                                               runner: runner) { box.append($0) }
        #expect(final == "result:claude-opus-4-8")
        #expect(runner.calls.count == 1)   // no plan/synthesize, just one answer
    }
}
