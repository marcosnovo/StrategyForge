//
//  ToolCheckTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for tool unit tests (article #5): the assertion engine + a run()
//  driven by a mock CommandRunner (no real process, no model).
//

import Testing
import Foundation
@testable import Coral

struct ToolCheckEngineTests {

    @Test func passesWhenExitZeroAndOutputContains() {
        let c = ToolCheck(name: "weather", command: "…", expectContains: "temp", expectExitZero: true)
        let r = ToolCheckEngine.evaluate(output: #"{"temp": 21}"#, exitCode: 0, check: c)
        #expect(r.passed)
    }

    @Test func failsOnNonZeroExit() {
        let c = ToolCheck(command: "…", expectContains: "", expectExitZero: true)
        let r = ToolCheckEngine.evaluate(output: "boom", exitCode: 1, check: c)
        #expect(!r.passed)
        #expect(r.reason.contains("1"))
    }

    @Test func failsWhenOutputMissingNeedle() {
        let c = ToolCheck(command: "…", expectContains: "temperature", expectExitZero: false)
        let r = ToolCheckEngine.evaluate(output: "cloudy", exitCode: 0, check: c)
        #expect(!r.passed)
        #expect(r.reason.contains("temperature"))
    }

    @Test func exitZeroCheckIgnoresOutputWhenNoNeedle() {
        let c = ToolCheck(command: "…", expectContains: "", expectExitZero: true)
        #expect(ToolCheckEngine.evaluate(output: "anything", exitCode: 0, check: c).passed)
    }

    @Test func noAssertionVacuouslyPassesButIsFlagged() {
        let c = ToolCheck(command: "…", expectContains: "", expectExitZero: false)
        #expect(!c.hasAssertion)
        let r = ToolCheckEngine.evaluate(output: "", exitCode: 0, check: c)
        #expect(r.passed)
        #expect(r.reason.contains("no assertion"))
    }
}

/// A CommandRunner that returns a scripted result per command substring.
private struct MockCommandRunner: CommandRunner {
    let byExit: Int32
    let output: String
    func run(_ command: String, cwd: String?) async -> (output: String, exitCode: Int32) {
        (output, byExit)
    }
}

struct ToolChecksRunTests {

    @Test func runsAndGradesEachCheck() async {
        let checks = [
            ToolCheck(name: "a", command: "echo hi", expectContains: "hi", expectExitZero: true),
            ToolCheck(name: "b", command: "echo hi", expectContains: "MISSING", expectExitZero: true),
        ]
        let runner = MockCommandRunner(byExit: 0, output: "hi there")
        let results = await ToolChecks.run(checks: checks, runner: runner, cwd: nil)
        #expect(results.count == 2)
        #expect(results[0].passed)
        #expect(!results[1].passed)     // needle "MISSING" not present
    }
}
