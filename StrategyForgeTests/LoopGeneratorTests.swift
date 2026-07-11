//
//  LoopGeneratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the Loop Builder's pure logic: file generation, the launch
//  command, tolerant LoopPlan decoding, and LoopWriter's STATE.md protection.
//

import Testing
import Foundation
@testable import StrategyForge

struct LoopFileGeneratorTests {

    private func makePlan(
        kind: LoopKind = .goalBased,
        verifier: Bool = true,
        memory: Bool = true
    ) -> LoopPlan {
        LoopPlan(
            name: "Fix auth",
            kind: kind,
            goal: "all tests in tests/auth pass and lint is clean",
            neverTouch: "migrations/",
            stopIf: "the CI config would need edits",
            maxTurns: 12,
            verifierEnabled: verifier,
            memoryEnabled: memory
        )
    }

    @Test func alwaysProducesLoopMdAndScript() {
        for kind in LoopKind.allCases {
            let files = LoopFileGenerator.generate(for: makePlan(kind: kind))
            let paths = Set(files.map(\.relativePath))
            #expect(paths.contains("LOOP.md"))
            #expect(paths.contains("loop.sh"))
        }
    }

    @Test func stateMdOnlyWhenMemoryEnabled() {
        let with = LoopFileGenerator.generate(for: makePlan(memory: true))
        #expect(with.contains { $0.relativePath == "STATE.md" })
        let state = with.first { $0.relativePath == "STATE.md" }!
        // The 5-section memory template.
        #expect(state.contents.contains("## Verified facts"))
        #expect(state.contents.contains("## General rules"))
        #expect(state.contents.contains("## Open failures (investigate next session)"))
        #expect(state.contents.contains("## Lessons learned"))
        #expect(state.contents.contains("## Last session"))

        let without = LoopFileGenerator.generate(for: makePlan(memory: false))
        #expect(!without.contains { $0.relativePath == "STATE.md" })
    }

    @Test func verifierFileRespectsToggleAndContract() {
        let files = LoopFileGenerator.generate(for: makePlan(verifier: true))
        let verifier = files.first { $0.relativePath == ".claude/agents/loop-verifier.md" }
        #expect(verifier != nil)
        let contents = verifier!.contents
        #expect(contents.contains("name: loop-verifier"))
        // Read-only tool set plus Bash (to run tests) — never Write/Edit.
        #expect(contents.contains("tools: Read, Grep, Glob, Bash"))
        #expect(!contents.contains("Write"))
        // The verifier pins its model (Haiku by default) in frontmatter.
        #expect(contents.contains("model: claude-haiku-4-5"))
        // Managed signature, so re-writes can prune it like other agent files.
        #expect(contents.contains(AgentFileGenerator.managedSignature))
        // The VERDICT contract the scripts grep for.
        #expect(contents.contains("VERDICT: PASS"))
        #expect(contents.contains("VERDICT: FAIL"))

        let none = LoopFileGenerator.generate(for: makePlan(verifier: false))
        #expect(!none.contains { $0.relativePath.contains("loop-verifier") })
    }

    @Test func loopMdContainsGoalAndTurnBrake() {
        let plan = makePlan()
        let loopMd = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(loopMd.contains(plan.goal))
        #expect(loopMd.contains("## Done when"))
        #expect(loopMd.contains("## Never touch"))
        #expect(loopMd.contains("- migrations/"))
        // The hard stop is spelled out under "Stop if".
        #expect(loopMd.contains("More than 12 turns"))
        // Extra stop conditions ride along.
        #expect(loopMd.contains("- the CI config would need edits"))
        // The memory rule appears when memory is on.
        #expect(loopMd.contains("Read STATE.md before starting. Update STATE.md before finishing."))
    }

    @Test func timeBasedLoopMdIncludesCronLine() {
        var plan = makePlan(kind: .timeBased)
        plan.intervalMinutes = 30
        plan.repoPath = "/Users/me/repo"
        let loopMd = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(loopMd.contains("*/30 * * * * cd /Users/me/repo && ./loop.sh >> logs/loop.log 2>&1"))
    }

    @Test func goalBasedLaunchCommandUsesModelAndGoal() {
        let plan = makePlan(kind: .goalBased)
        let cmd = LoopFileGenerator.launchCommand(for: plan, binary: "claude")
        #expect(cmd.contains("--model claude-sonnet-5"))
        #expect(cmd.contains("/goal"))
        #expect(cmd.contains("max 12 turns"))
        // The other kinds launch through the script.
        for kind in [LoopKind.turnBased, .timeBased, .proactive] {
            #expect(LoopFileGenerator.launchCommand(for: makePlan(kind: kind), binary: "claude") == "./loop.sh")
        }
    }

    @Test func scriptsEmbedTheBrakeAndVerdictCheck() {
        let plan = makePlan(kind: .goalBased)
        let script = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "loop.sh" }!.contents
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("MAX_TURNS=12"))
        #expect(script.contains("VERDICT: PASS"))
        #expect(script.contains("loop-verifier"))
    }
}

struct LoopPlanCodableTests {

    @Test func tolerantDecodeFromMinimalJSON() throws {
        let data = Data(#"{"name":"x"}"#.utf8)
        let plan = try JSONDecoder().decode(LoopPlan.self, from: data)
        #expect(plan.name == "x")
        #expect(plan.kind == .goalBased)
        #expect(plan.maxTurns == 20)
        #expect(plan.intervalMinutes == 30)
        #expect(plan.workerModel == .sonnet5)
        #expect(plan.verifierEnabled)
        #expect(plan.verifierModel == .haiku45)
        #expect(plan.memoryEnabled)
        #expect(plan.repoPath == nil)
        #expect(plan.lastRunAt == nil)
    }

    @Test func decodeClampsTurnsAndTolersUnknownEnums() throws {
        let data = Data(#"{"name":"x","maxTurns":9999,"kind":"future-kind","workerModel":"claude-99"}"#.utf8)
        let plan = try JSONDecoder().decode(LoopPlan.self, from: data)
        #expect(plan.maxTurns == 100)
        #expect(plan.kind == .goalBased)
        #expect(plan.workerModel == .sonnet5)
    }

    @Test func validateReturnsLocalizationKeys() {
        var plan = LoopPlan(name: "", kind: .goalBased, goal: "", verifierEnabled: false)
        let issues = plan.validate()
        #expect(issues.contains("loop.issue.name"))
        #expect(issues.contains("loop.issue.goal"))
        #expect(issues.contains("loop.issue.noVerifier"))

        plan.name = "n"; plan.goal = "tests pass"; plan.verifierEnabled = true
        #expect(plan.validate().isEmpty)
        #expect(!plan.isRunnable)          // still no repo
        plan.repoPath = "/tmp/repo"
        #expect(plan.isRunnable)
    }
}

struct LoopWriterTests {

    private func tempRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loop-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func neverOverwritesExistingStateMd() throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let plan = LoopPlan(name: "Loop", goal: "tests pass")
        let writer = LoopWriter(repoURL: repo)

        let first = try writer.write(plan: plan)
        #expect(first.contains("STATE.md"))

        // Simulate accumulated memory, then re-generate.
        let stateURL = repo.appendingPathComponent("STATE.md")
        let memory = "# STATE.md\n\n## Verified facts\n- the bug is in TokenStore\n"
        try memory.write(to: stateURL, atomically: true, encoding: .utf8)

        let second = try writer.write(plan: plan)
        // Skipped silently: not reported as written, contents untouched.
        #expect(!second.contains("STATE.md"))
        #expect(try String(contentsOf: stateURL, encoding: .utf8) == memory)
        // Everything else still (re)written.
        #expect(second.contains("LOOP.md"))
        #expect(second.contains("loop.sh"))
    }

    @Test func marksLoopShExecutableAndInjectsBinary() throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let plan = LoopPlan(name: "Loop", kind: .turnBased, goal: "tests pass")
        try LoopWriter(repoURL: repo, binary: "/usr/local/bin/claude").write(plan: plan)

        let scriptURL = repo.appendingPathComponent("loop.sh")
        let attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        #expect(perms & 0o111 != 0)   // executable bits set

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(script.contains("BINARY=\"/usr/local/bin/claude\""))
    }

    @Test func createsIntermediateDirectories() throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let plan = LoopPlan(name: "Loop", goal: "tests pass")   // verifier on by default
        try LoopWriter(repoURL: repo).write(plan: plan)
        let verifier = repo.appendingPathComponent(".claude/agents/loop-verifier.md")
        #expect(FileManager.default.fileExists(atPath: verifier.path))
    }
}
