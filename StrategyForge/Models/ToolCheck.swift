//
//  ToolCheck.swift
//  StrategyForge
//
//  Tool unit tests (the '10 agent evals' article, #5): "test each tool on its own, with
//  fixtures, no model in the loop — most agent bugs are tool bugs wearing a costume."
//  A ToolCheck runs a deterministic command (the tool invocation) and asserts on its
//  output/exit code — no LLM, so it's fast, cheap, and repeatable. Travels with the team.
//

import Foundation

/// One deterministic tool check: run `command`, assert on the result.
struct ToolCheck: Codable, Identifiable, Hashable {
    var id: UUID
    /// A human name, e.g. "weather MCP returns a temperature".
    var name: String
    /// The tool invocation to run in a shell — a curl, a skill script, an MCP probe, etc.
    var command: String
    /// stdout+stderr must CONTAIN this (empty = don't assert on output).
    var expectContains: String
    /// The command must exit 0.
    var expectExitZero: Bool

    init(id: UUID = UUID(), name: String = "", command: String = "",
         expectContains: String = "", expectExitZero: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.expectContains = expectContains
        self.expectExitZero = expectExitZero
    }

    /// A check with no assertion at all can only ever vacuously pass — the UI uses this to
    /// warn, and the runner treats it as "just ran".
    var hasAssertion: Bool {
        expectExitZero || !expectContains.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// The verdict for one tool check after running.
struct ToolCheckResult: Identifiable, Hashable, Sendable {
    var checkID: UUID
    var passed: Bool
    var reason: String
    var id: UUID { checkID }
}

/// Pure evaluation of a captured command result against a check — no process, no model,
/// so it's directly unit-tested.
enum ToolCheckEngine {
    static func evaluate(output: String, exitCode: Int32, check: ToolCheck) -> ToolCheckResult {
        if check.expectExitZero && exitCode != 0 {
            return ToolCheckResult(checkID: check.id, passed: false, reason: "exited \(exitCode)")
        }
        let needle = check.expectContains.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty && !output.contains(needle) {
            return ToolCheckResult(checkID: check.id, passed: false,
                                   reason: "output didn't contain “\(needle)”")
        }
        return ToolCheckResult(checkID: check.id, passed: true,
                               reason: check.hasAssertion ? "passed" : "ran (no assertion)")
    }
}
