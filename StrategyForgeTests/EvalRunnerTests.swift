//
//  EvalRunnerTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for the eval engine (scenario parsing, judge-verdict parsing,
//  scoring/gate) plus a run() integration driven by mock OneShotRunners.
//

import Testing
import Foundation
@testable import Coral

struct EvalParsingTests {

    @Test func parsesScenariosTolerantly() {
        let text = """
        Here you go:
        [
          {"prompt":"How to merge dicts?","expectation":"cites a source","category":"citation"},
          {"prompt":"2022 World Cup?","expectation":"declines, out of scope","category":"refusesWhenUnknown"},
          {"bad":"missing fields"},
          {"prompt":"multi","expectation":"combines two facts","category":"unknownCat"}
        ]
        """
        let scenarios = EvalRunner.parseScenarios(text)
        #expect(scenarios.count == 3)                                   // the malformed entry is dropped
        #expect(scenarios[0].category == .citation)
        #expect(scenarios[1].category == .refusesWhenUnknown)
        #expect(scenarios[2].category == .answersCorrectly)            // unknown category → default
    }

    @Test func emptyOnGarbage() {
        #expect(EvalRunner.parseScenarios("no json here").isEmpty)
    }

    @Test func parsesVerdictAndDefaultsToFailOnGarbage() {
        #expect(EvalRunner.parseVerdict(#"{"pass": true, "reason":"good"}"#) == (true, "good"))
        #expect(EvalRunner.parseVerdict(#"prefix {"pass": false, "reason":"missing citation"} suffix"#).passed == false)
        // Unparseable → never a false pass.
        #expect(EvalRunner.parseVerdict("the model rambled").passed == false)
        // String "yes" is accepted as pass.
        #expect(EvalRunner.parseVerdict(#"{"pass":"yes","reason":""}"#).passed == true)
    }
}

struct EvalScoringTests {

    private func results(_ passes: [Bool]) -> [EvalResult] {
        passes.map { EvalResult(scenarioID: UUID(), passed: $0, reason: "") }
    }

    @Test func passRateAndGate() {
        let run = EvalRun(results: results([true, true, true, false]), threshold: 0.7)
        #expect(run.passed == 3)
        #expect(run.total == 4)
        #expect(abs(run.passRate - 0.75) < 0.0001)
        #expect(run.meetsThreshold)                                   // 0.75 ≥ 0.70

        let below = EvalRun(results: results([true, false, false, false]), threshold: 0.7)
        #expect(!below.meetsThreshold)                               // 0.25 < 0.70

        let empty = EvalRun(results: [], threshold: 0.0)
        #expect(!empty.meetsThreshold)                               // an empty run never passes
    }
}

/// A OneShotRunner that returns a fixed text per call (round-robins if several given).
private struct ScriptedRunner: OneShotRunner {
    let replies: [String]
    final class Counter: @unchecked Sendable { var i = 0 }
    let counter = Counter()
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        let text = replies[counter.i % replies.count]
        counter.i += 1
        return OneShotResult(text: text, tokens: 0, costUSD: 0, provider: provider, model: model)
    }
}

@MainActor
struct EvalRunIntegrationTests {

    @Test func runScoresEachScenarioViaTheJudge() async {
        let team = StrategyLibrary.orchestratorWorkers()
        let suite = EvalSuite(scenarios: [
            EvalScenario(prompt: "q1", expectation: "e1", category: .answersCorrectly),
            EvalScenario(prompt: "q2", expectation: "e2", category: .refusesWhenUnknown),
        ], passThreshold: 0.5)

        let answerRunner = ScriptedRunner(replies: ["answer text"])
        // Judge passes the first, fails the second.
        let judgeRunner = ScriptedRunner(replies: [
            #"{"pass": true, "reason":"ok"}"#,
            #"{"pass": false, "reason":"hallucinated"}"#,
        ])

        let run = await EvalRunner.run(team: team, suite: suite, cwd: nil,
                                       answerRunner: answerRunner, judgeRunner: judgeRunner)
        #expect(run.total == 2)
        #expect(run.passed == 1)
        #expect(run.meetsThreshold)                                  // 0.5 ≥ 0.5
        #expect(run.results[1].reason == "hallucinated")
    }
}
