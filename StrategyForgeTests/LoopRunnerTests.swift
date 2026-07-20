//
//  LoopRunnerTests.swift
//  StrategyForgeTests
//
//  Unit tests for the in-app loop runner's pure logic: the mechanical verify
//  gate (command flattening + real execution via bash) and the verifier
//  prompt's '## Must still hold' guardrail.
//

import Testing
import Foundation
@testable import Coral

struct LoopRunnerTests {

    private func makePlan(goal: String = "all tests pass",
                          mustHold: String = "",
                          verifyCommand: String = "") -> LoopPlan {
        LoopPlan(name: "Fix auth",
                 kind: .goalBased,
                 goal: goal,
                 mustHold: mustHold,
                 verifyCommand: verifyCommand,
                 verifierEnabled: true)
    }

    // MARK: - Mechanical gate: command flattening

    @MainActor @Test func mechanicalCommandKeepsTrimmedLinesVerbatim() {
        // Lines stay verbatim one per line (blank lines dropped, whitespace
        // trimmed) — the same shape LoopFileGenerator.mechVerify feeds the
        // generated loop.sh's `bash -e` gate.
        let plan = makePlan(verifyCommand: "swift build\n  swift test  \n\n")
        #expect(LoopRunController.mechanicalCommand(plan: plan) == "swift build\nswift test")
    }

    @MainActor @Test func mechanicalCommandEmptyWhenUnset() {
        #expect(LoopRunController.mechanicalCommand(plan: makePlan()).isEmpty)
        #expect(LoopRunController.mechanicalCommand(plan: makePlan(verifyCommand: "  \n ")).isEmpty)
    }

    // MARK: - Mechanical gate: execution

    @Test func gatePassesOnExitZero() async {
        let result = await LoopRunController.runMechanicalGate("true", cwd: NSTemporaryDirectory())
        #expect(result == nil)
    }

    @Test func gateFailureCarriesCommandExitCodeAndOutput() async {
        let result = await LoopRunController.runMechanicalGate("echo boom >&2; exit 3",
                                                               cwd: NSTemporaryDirectory())
        #expect(result != nil)
        #expect(result?.contains("exit 3") == true)     // the exit code
        #expect(result?.contains("boom") == true)       // the output tail
        #expect(result?.contains("echo boom") == true)  // the command itself
    }

    @Test func gateRequiresEveryLineToPass() async {
        // `set -e` semantics: a failing middle line fails the whole gate…
        let failing = await LoopRunController.runMechanicalGate("true\nfalse\ntrue",
                                                                cwd: NSTemporaryDirectory())
        #expect(failing != nil)
        // …while a `#` comment line is harmless (it must not swallow what follows).
        let commented = await LoopRunController.runMechanicalGate("# a comment\ntrue",
                                                                  cwd: NSTemporaryDirectory())
        #expect(commented == nil)
    }

    @Test func gateRunsInTheGivenDirectory() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-gate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("marker").path,
                                       contents: Data())
        let found = await LoopRunController.runMechanicalGate("test -f marker", cwd: dir.path)
        #expect(found == nil)
        let missing = await LoopRunController.runMechanicalGate("test -f nope", cwd: dir.path)
        #expect(missing != nil)
    }

    @Test func gateTimeoutKillsAHungCommand() async {
        // A hung verify command must not hang the loop forever: the watchdog
        // terminates it and the gate reads as a FAIL.
        let result = await LoopRunController.runMechanicalGate("sleep 30",
                                                               cwd: NSTemporaryDirectory(),
                                                               timeout: 1)
        #expect(result != nil)
    }

    // MARK: - Verifier prompt: the mustHold guardrail

    @MainActor @Test func verifierPromptUnchangedWhenMustHoldEmpty() {
        let prompt = LoopRunController.verifierPrompt(plan: makePlan())
        #expect(prompt.contains("ONLY against this '## Done when' goal"))
        #expect(!prompt.contains("Must still hold"))
        #expect(prompt.contains("`VERDICT: PASS` or `VERDICT: FAIL`"))
    }

    @MainActor @Test func verifierPromptCarriesMustHoldCounterConditions() {
        let plan = makePlan(mustHold: "no test was deleted or skipped")
        let prompt = LoopRunController.verifierPrompt(plan: plan)
        // The counter-conditions are spelled out, with the FAIL-even-if-met rule…
        #expect(prompt.contains("no test was deleted or skipped"))
        #expect(prompt.contains("FAIL even when the goal looks met"))
        // …and the old "ONLY the goal" steer (which told the judge to disregard
        // them) is gone.
        #expect(!prompt.contains("ONLY against"))
        #expect(prompt.contains("`VERDICT: PASS` or `VERDICT: FAIL`"))
    }
}
