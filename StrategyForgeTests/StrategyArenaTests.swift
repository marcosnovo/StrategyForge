//
//  StrategyArenaTests.swift
//  StrategyForgeTests
//
//  The team arena: the pure progress reducer (MetaEvent → StrategyRunProgress) and the
//  concurrent engine that races whole strategies through MetaOrchestrator with a mock
//  runner — accumulating usage, isolating a losing contestant, and suggesting the cheapest
//  successful team as the winner.
//

import Testing
import Foundation
@testable import Coral

private struct FakeStrategyRunner: OneShotRunner {
    /// Providers that should throw instead of answering (to fail a whole team).
    var failing: Set<AIProvider> = []
    var tokensPerCall: Int = 10
    var costPerCall: Double = 0.01
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        if failing.contains(provider) { throw OneShotError.failed("\(provider.displayName) down") }
        return OneShotResult(text: "answer from \(provider.displayName)", tokens: tokensPerCall,
                             costUSD: costPerCall, provider: provider, model: model)
    }
}

struct StrategyProgressReducerTests {

    @Test func accumulatesUsageAndTracksActiveRoles() {
        var p = StrategyRunProgress()
        p = StrategyProgressReducer.reduce(p, .phase("plan"))
        #expect(p.state == .running)
        #expect(p.phase == "plan")

        p = StrategyProgressReducer.reduce(p, .roleStarted(role: "coder", provider: .openai, model: "gpt-5", task: "write it"))
        #expect(p.activeRoles == ["coder"])
        #expect(p.lastNarration == "coder: write it")

        p = StrategyProgressReducer.reduce(p, .usage(tokens: 100, costUSD: 0.02))
        p = StrategyProgressReducer.reduce(p, .usage(tokens: 50, costUSD: 0.01))
        #expect(p.tokens == 150)                     // per-call usage accumulates
        #expect(abs(p.costUSD - 0.03) < 1e-9)

        p = StrategyProgressReducer.reduce(p, .roleFinished(role: "coder", tokens: 50))
        #expect(p.activeRoles.isEmpty)
        #expect(p.finishedRoles == ["coder"])

        p = StrategyProgressReducer.reduce(p, .assistantText("final"))
        p = StrategyProgressReducer.reduce(p, .finished)
        #expect(p.state == .done)
        #expect(p.answer == "final")
    }

    @Test func failureIsTerminalAndEstimatedIsSticky() {
        var p = StrategyRunProgress()
        p = StrategyProgressReducer.reduce(p, .usage(tokens: 10, costUSD: 0, estimated: true))
        #expect(p.estimated)
        p = StrategyProgressReducer.reduce(p, .failed("boom"))
        #expect(p.state == .failed)
        #expect(p.error == "boom")
    }
}

struct StrategyArenaEngineTests {

    private func contestants() -> [StrategyContestant] {
        [
            StrategyContestant(id: "fanout", name: "Fan-out", strategy: StrategyLibrary.orchestratorWorkers()),
            StrategyContestant(id: "advisor", name: "Advisor", strategy: StrategyLibrary.executorAdvisor()),
        ]
    }

    @Test func racesEveryContestantToADoneState() async {
        var updates = 0
        let finals = await StrategyArenaEngine.run(
            task: "do the thing", cwd: nil, contestants: contestants(),
            runner: FakeStrategyRunner()) { _, _ in updates += 1 }
        #expect(finals.count == 2)
        #expect(finals["fanout"]?.state == .done)
        #expect(finals["advisor"]?.state == .done)
        #expect(finals["fanout"]?.answer?.isEmpty == false)
        #expect(updates > 0)                          // progress streamed, never silent
    }

    @Test func aTeamWhoseProviderFailsStillTerminatesWithoutSinkingTheArena() async {
        // Fail every OpenAI call. The advisor team (executor+advisor) leans on providers;
        // whatever its makeup, one failing provider must not hang or crash the arena — the
        // other team still finishes and the arena returns terminal states for both.
        let finals = await StrategyArenaEngine.run(
            task: "x", cwd: nil, contestants: contestants(),
            runner: FakeStrategyRunner(failing: [.openai, .gemini])) { _, _ in }
        #expect(finals.count == 2)
        #expect(finals.values.allSatisfy { $0.state == .done || $0.state == .failed })
    }

    @Test func suggestedWinnerIsCheapestDoneTeam() {
        let finals: [String: StrategyRunProgress] = [
            "a": StrategyRunProgress(state: .done, tokens: 100, costUSD: 0.05, answer: "a"),
            "b": StrategyRunProgress(state: .done, tokens: 80, costUSD: 0.02, answer: "b"),
            "c": StrategyRunProgress(state: .failed, error: "x"),
        ]
        #expect(StrategyArenaEngine.suggestedWinner(finals) == "b")
    }

    @Test func noWinnerWhenAllFailed() {
        let finals: [String: StrategyRunProgress] = [
            "a": StrategyRunProgress(state: .failed, error: "x"),
        ]
        #expect(StrategyArenaEngine.suggestedWinner(finals) == nil)
    }
}
