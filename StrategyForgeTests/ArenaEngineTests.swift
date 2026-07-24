//
//  ArenaEngineTests.swift
//  StrategyForgeTests
//
//  The Arena fan-out: every entrant runs, results come back in entrant order, one
//  entrant's failure is isolated (never sinks the arena), and the cheapest successful
//  run is suggested as the default winner.
//

import Testing
import Foundation
@testable import Coral

/// A scriptable OneShotRunner: per-provider canned result or thrown error.
private struct FakeArenaRunner: OneShotRunner {
    var results: [AIProvider: OneShotResult] = [:]
    var failures: [AIProvider: OneShotError] = [:]
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        if let e = failures[provider] { throw e }
        if let r = results[provider] { return r }
        return OneShotResult(text: "\(provider.displayName): \(prompt)", tokens: 10, costUSD: 0.01,
                             provider: provider, model: model)
    }
}

struct ArenaEngineTests {

    private let entrants: [ArenaEntrant] = [
        ArenaEntrant(provider: .claude, model: "opus"),
        ArenaEntrant(provider: .openai, model: "gpt-5"),
        ArenaEntrant(provider: .gemini, model: "gemini-2.5-pro"),
    ]

    @Test func runsEveryEntrantAndPreservesOrder() async {
        let out = await ArenaEngine.run(prompt: "hi", entrants: entrants, cwd: nil, runner: FakeArenaRunner())
        #expect(out.map(\.entrant.provider) == [.claude, .openai, .gemini])
        #expect(out.allSatisfy { $0.succeeded })
        #expect(out[0].result?.text.contains("hi") == true)
    }

    @Test func oneEntrantFailingDoesNotSinkTheArena() async {
        let runner = FakeArenaRunner(failures: [.openai: .notInstalled(.openai)])
        let out = await ArenaEngine.run(prompt: "hi", entrants: entrants, cwd: nil, runner: runner)
        #expect(out.count == 3)
        let openai = out.first { $0.entrant.provider == .openai }!
        #expect(!openai.succeeded)
        #expect(openai.error?.isEmpty == false)
        // The others still succeeded.
        #expect(out.filter { $0.succeeded }.count == 2)
    }

    @Test func suggestedWinnerIsCheapestSuccessfulRun() async {
        let runner = FakeArenaRunner(results: [
            .claude: OneShotResult(text: "a", tokens: 100, costUSD: 0.05, provider: .claude, model: "opus"),
            .openai: OneShotResult(text: "b", tokens: 80, costUSD: 0.02, provider: .openai, model: "gpt-5"),
            .gemini: OneShotResult(text: "c", tokens: 90, costUSD: 0.02, provider: .gemini, model: "gemini-2.5-pro"),
        ])
        let out = await ArenaEngine.run(prompt: "x", entrants: entrants, cwd: nil, runner: runner)
        // openai + gemini tie on cost (0.02); openai wins on fewer tokens (80 < 90).
        #expect(ArenaEngine.suggestedWinner(out) == "openai:gpt-5")
    }

    @Test func emptyEntrantsYieldNoOutcomes() async {
        let out = await ArenaEngine.run(prompt: "x", entrants: [], cwd: nil, runner: FakeArenaRunner())
        #expect(out.isEmpty)
        #expect(ArenaEngine.suggestedWinner(out) == nil)
    }

    @Test func allFailingHasNoSuggestedWinner() async {
        let runner = FakeArenaRunner(failures: [
            .claude: .failed("x"), .openai: .failed("y"), .gemini: .timedOut(600),
        ])
        let out = await ArenaEngine.run(prompt: "x", entrants: entrants, cwd: nil, runner: runner)
        #expect(out.allSatisfy { !$0.succeeded })
        #expect(ArenaEngine.suggestedWinner(out) == nil)
    }
}
