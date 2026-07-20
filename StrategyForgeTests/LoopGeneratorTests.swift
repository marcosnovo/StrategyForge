//
//  LoopGeneratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the Loop Builder's pure logic: file generation, the launch
//  command, tolerant LoopPlan decoding, and LoopWriter's STATE.md protection.
//

import Testing
import Foundation
@testable import Coral

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

    // MARK: - Loops-zone hardening (#4)

    @Test func cronLineQuotesTheRepoPath() {
        // A repo path with a space must be single-quoted in the crontab example, or the
        // line breaks (or injects). Time-based loops embed the cron line in loop.sh.
        var plan = makePlan(kind: .timeBased)
        plan.repoPath = "/Users/me/My Projects/app"
        let sh = script(LoopFileGenerator.generate(for: plan))
        #expect(sh.contains("cd '/Users/me/My Projects/app'"))
    }

    @Test func capturedVerifyIsFaultTolerantUnderSetE() {
        // The judge is captured with `|| true` so a transient failure can't trip set -e
        // and kill the whole goal loop.
        let sh = script(LoopFileGenerator.generate(for: makePlan(kind: .goalBased)))
        #expect(sh.contains("VERDICT=\"$("))
        #expect(sh.contains("|| true)\""))
    }

    @Test func worktreeTrapDoesNotMergeErrLog() {
        var plan = makePlan(kind: .goalBased)
        plan.useWorktree = true
        let sh = script(LoopFileGenerator.generate(for: plan))
        #expect(sh.contains("git reset -q -- err.log"))
    }

    // MARK: - Worktree isolation (opt-in)

    private func script(_ files: [GeneratedFile]) -> String {
        files.first { $0.relativePath == "loop.sh" }!.contents
    }

    @Test func worktreeOffLeavesTheScriptUntouched() {
        // Default (off) must be byte-identical to before: no worktree machinery anywhere.
        for kind in LoopKind.allCases {
            let sh = script(LoopFileGenerator.generate(for: makePlan(kind: kind)))
            #expect(!sh.contains("worktree"))
            #expect(!sh.contains("coral_finish"))
        }
    }

    @Test func worktreeOnInjectsPreambleAndGate() {
        var plan = makePlan(kind: .goalBased)
        plan.useWorktree = true
        let sh = script(LoopFileGenerator.generate(for: plan))
        // The preamble sets up an isolated tree and installs the merge-gating trap.
        #expect(sh.contains("git worktree add -b \"$CORAL_BRANCH\""))
        #expect(sh.contains("trap coral_finish EXIT"))
        #expect(sh.contains("loop/fix-auth-"))            // branch slug from the name
        // Merge ONLY on a verified PASS; every other outcome leaves the branch.
        #expect(sh.contains("VERDICT: PASS"))
        #expect(sh.contains("merge --no-ff"))
        #expect(sh.contains("left this run on branch"))
        // The trap is installed only after cd, so a failed add can't touch the main tree.
        let cdIdx = sh.range(of: "cd \"$CORAL_WT\"")!.lowerBound
        let trapIdx = sh.range(of: "trap coral_finish EXIT")!.lowerBound
        #expect(cdIdx < trapIdx)
    }

    @Test func worktreeCarriesScaffoldingForEveryKind() {
        for kind in LoopKind.allCases {
            var plan = makePlan(kind: kind)
            plan.useWorktree = true
            let sh = script(LoopFileGenerator.generate(for: plan))
            #expect(sh.contains("loop-verifier.md"))       // copies the verifier in
            #expect(sh.contains("trap coral_finish EXIT"))  // wraps all four kinds
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

    @Test func mechanicalGateRunsBeforeTheJudgeAndFailsOnNonZeroExit() {
        var plan = makePlan(kind: .goalBased)
        plan.verifyCommand = "swift build\nswift test"     // two lines → both must pass
        let files = LoopFileGenerator.generate(for: plan)
        let loopMd = files.first { $0.relativePath == "LOOP.md" }!.contents
        // Documented as the mechanical gate, lines verbatim.
        #expect(loopMd.contains("## Verify command (mechanical gate)"))
        #expect(loopMd.contains("```\nswift build\nswift test\n```"))
        // The script gates on the gate's exit code: only exit 0 reaches the judge,
        // a non-zero exit is FAIL with no LLM call.
        let sh = script(files)
        #expect(sh.contains("if bash -e >/dev/null 2>&1 <<'CORAL_VERIFY'\nswift build\nswift test\nCORAL_VERIFY\nthen"))
        #expect(sh.contains("VERDICT: FAIL"))
    }

    @Test func mechanicalGateKeepsHostileCommandLinesVerbatim() {
        // A `#` comment or trailing `&&` in the user's command must not be able to
        // break loop.sh's own syntax: each line lands verbatim inside the heredoc,
        // never flattened onto one line where a comment would eat the rest.
        var plan = makePlan(kind: .goalBased)
        plan.verifyCommand = "make build   # quick\nmake test &&"
        let sh = script(LoopFileGenerator.generate(for: plan))
        #expect(sh.contains("<<'CORAL_VERIFY'\nmake build   # quick\nmake test &&\nCORAL_VERIFY\n"))
        #expect(!sh.contains("# quick && make test"))
    }

    @Test func noVerifyCommandKeepsTheJudgeOnlyGate() {
        let sh = script(LoopFileGenerator.generate(for: makePlan(kind: .goalBased)))  // verifyCommand = ""
        #expect(!sh.contains("CORAL_VERIFY"))              // no mechanical wrapper
    }

    @Test func verifyCommandDecodesTolerantlyAndDefaultsEmpty() throws {
        let plan = try JSONDecoder().decode(LoopPlan.self, from: Data(#"{"name":"L","goal":"g"}"#.utf8))
        #expect(plan.verifyCommand == "")
        var withCmd = plan; withCmd.verifyCommand = "make test"
        let round = try JSONDecoder().decode(LoopPlan.self, from: JSONEncoder().encode(withCmd))
        #expect(round.verifyCommand == "make test")
    }

    @Test func failReasonIsWrittenBackToStateWhenMemoryAndVerifierOn() {
        // Self-improving loop: a rejection reason recorded in STATE.md doesn't recur.
        let withBoth = LoopFileGenerator.generate(for: makePlan(verifier: true, memory: true))
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(withBoth.contains("VERDICT: FAIL"))
        #expect(withBoth.contains("write its reason into STATE.md"))
        // No verifier → nothing to write back.
        let noVerifier = LoopFileGenerator.generate(for: makePlan(verifier: false, memory: true))
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(!noVerifier.contains("write its reason into STATE.md"))
    }

    @Test func mustHoldGuardrailAppearsInLoopMdAndVerifier() {
        var plan = makePlan()
        plan.mustHold = "no test was deleted or skipped\ncoverage did not drop"
        let files = LoopFileGenerator.generate(for: plan)
        let loopMd = files.first { $0.relativePath == "LOOP.md" }!.contents
        // The counter-conditions land under a dedicated section, as bullets.
        #expect(loopMd.contains("## Must still hold"))
        #expect(loopMd.contains("- no test was deleted or skipped"))
        #expect(loopMd.contains("- coverage did not drop"))
        // The verifier is told to FAIL a gamed goal.
        let verifier = files.first { $0.relativePath == ".claude/agents/loop-verifier.md" }!.contents
        #expect(verifier.contains("## Must still hold"))
        #expect(verifier.contains("FAIL even if 'Done when' is met"))
    }

    @Test func noMustHoldSectionWhenEmpty() {
        let files = LoopFileGenerator.generate(for: makePlan())   // mustHold defaults to ""
        let loopMd = files.first { $0.relativePath == "LOOP.md" }!.contents
        #expect(!loopMd.contains("## Must still hold"))
        let verifier = files.first { $0.relativePath == ".claude/agents/loop-verifier.md" }!.contents
        #expect(!verifier.contains("Must still hold"))
    }

    @Test func mustHoldDecodesTolerantlyAndDefaultsEmpty() throws {
        // A plan JSON without mustHold (older version) decodes with an empty guardrail.
        let json = #"{"name":"L","goal":"g"}"#
        let plan = try JSONDecoder().decode(LoopPlan.self, from: Data(json.utf8))
        #expect(plan.mustHold == "")
        // Round-trips when set.
        var withGuard = plan
        withGuard.mustHold = "x holds"
        let round = try JSONDecoder().decode(LoopPlan.self, from: JSONEncoder().encode(withGuard))
        #expect(round.mustHold == "x holds")
    }

    @Test func timeBasedLoopMdIncludesCronLine() {
        var plan = makePlan(kind: .timeBased)
        plan.intervalMinutes = 30
        plan.repoPath = "/Users/me/repo"
        let loopMd = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "LOOP.md" }!.contents
        // mkdir -p makes the line self-sufficient on a fresh install, where loop.sh
        // hasn't yet created logs/ — otherwise cron's redirect fails silently forever.
        #expect(loopMd.contains("*/30 * * * * cd '/Users/me/repo' && mkdir -p logs && ./loop.sh >> logs/loop.log 2>&1"))
    }

    @Test func cronLineNeverRoundsToAMoreFrequentSchedule() {
        // 90 min isn't a whole-hour multiple (only hand-edited persistence produces
        // it): the instruction rounds UP to 2 hours instead of over-firing at */30.
        var plan = makePlan(kind: .timeBased)
        plan.intervalMinutes = 90
        plan.repoPath = "/Users/me/repo"
        let loopMd = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(loopMd.contains("0 */2 * * * cd '/Users/me/repo'"))
        #expect(!loopMd.contains("*/30 * * * *"))
        // Whole-hour multiples keep their exact cadence.
        plan.intervalMinutes = 120
        let twoHours = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "LOOP.md" }!.contents
        #expect(twoHours.contains("0 */2 * * * cd '/Users/me/repo'"))
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
        #expect(script.contains("grep -m1 \"VERDICT:\" | grep -q \"PASS\""))
        #expect(script.contains("loop-verifier"))
    }

    @Test func passDetectionReadsTheFirstVerdictLineOnly() {
        // A FAIL reply that merely QUOTES 'VERDICT: PASS' in its bullet reasons must
        // not read as a PASS: detection anchors on the first line carrying VERDICT:
        // (mirroring the in-app parseVerdict), never a substring of the whole reply.
        let sh = script(LoopFileGenerator.generate(for: makePlan(kind: .goalBased)))
        #expect(sh.contains("if printf '%s\\n' \"$VERDICT\" | grep -m1 \"VERDICT:\" | grep -q \"PASS\"; then"))
        #expect(!sh.contains("*\"VERDICT: PASS\"*"))       // the old whole-reply match

        // The worktree trap gates its merge with the same first-verdict-line pipeline.
        var wt = makePlan(kind: .goalBased)
        wt.useWorktree = true
        let wtSh = script(LoopFileGenerator.generate(for: wt))
        #expect(wtSh.contains("[ \"$code\" -eq 0 ] && printf '%s\\n' \"$VERDICT\" | grep -m1 \"VERDICT:\" | grep -q \"PASS\""))
    }

    // MARK: - Effort (gap #3)

    @Test func everyScriptKindCarriesTheEffortFlag() {
        for kind in LoopKind.allCases {
            var plan = makePlan(kind: kind)
            plan.effort = .high
            let script = LoopFileGenerator.generate(for: plan)
                .first { $0.relativePath == "loop.sh" }!.contents
            #expect(script.contains("EFFORT=\"high\""))
            #expect(script.contains("--effort \"$EFFORT\""))
        }
    }

    @Test func goalLaunchCommandCarriesEffort() {
        var plan = makePlan(kind: .goalBased)
        plan.effort = .high
        let cmd = LoopFileGenerator.launchCommand(for: plan, binary: "claude")
        #expect(cmd.contains("--effort high"))
    }

    // MARK: - Circuit breaker (gap #2)

    @Test func goalScriptAlwaysHasCircuitBreaker() {
        // Present regardless of budget: it's pure safety, not tied to the cap.
        let script = LoopFileGenerator.generate(for: makePlan(kind: .goalBased))
            .first { $0.relativePath == "loop.sh" }!.contents
        #expect(script.contains("MAX_FAILS=3"))
        #expect(script.contains("Circuit breaker"))
        #expect(script.contains("exit 2"))
    }

    // MARK: - Budget cap (gap #1)

    @Test func budgetIsOffByDefault() {
        let script = LoopFileGenerator.generate(for: makePlan(kind: .goalBased))
            .first { $0.relativePath == "loop.sh" }!.contents
        #expect(!script.contains("BUDGET_USD"))
        #expect(!script.contains("extract_cost"))
    }

    @Test func budgetWhenSetEmitsCapAndCostReader() {
        var plan = makePlan(kind: .goalBased)
        plan.budgetUSD = 5
        let script = LoopFileGenerator.generate(for: plan)
            .first { $0.relativePath == "loop.sh" }!.contents
        #expect(script.contains("BUDGET_USD=5"))
        #expect(script.contains("--output-format json"))   // needed to read the cost
        #expect(script.contains("extract_cost"))
        #expect(script.contains("total_cost_usd"))
        #expect(script.contains("exit 3"))                  // the budget-stop exit code
        // Native per-invocation cap too (documented flag) — bounds each call,
        // including the verifier, even if the cumulative tally can't read the field.
        #expect(script.contains("--max-budget-usd \"$BUDGET_USD\""))
    }

    @Test func budgetIsGoalLoopOnly() {
        // Other kinds run a single pass, so a post-hoc cap is meaningless there.
        for kind in [LoopKind.turnBased, .timeBased, .proactive] {
            var plan = makePlan(kind: kind)
            plan.budgetUSD = 5
            let script = LoopFileGenerator.generate(for: plan)
                .first { $0.relativePath == "loop.sh" }!.contents
            #expect(!script.contains("BUDGET_USD"))
        }
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

    @Test func decodeClampsTurnsAndToleratesUnknownEnums() throws {
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

    // MARK: - Effort + budget defaults / round-trip (gaps #1, #3)

    @Test func decodeDefaultsEffortAndBudget() throws {
        let plan = try JSONDecoder().decode(LoopPlan.self, from: Data(#"{"name":"x"}"#.utf8))
        #expect(plan.effort == .medium)
        #expect(plan.budgetUSD == nil)
    }

    @Test func decodeReadsEffortAndBudgetAndClampsNegative() throws {
        let json = #"{"name":"x","effort":"high","budgetUSD":7.5}"#
        let plan = try JSONDecoder().decode(LoopPlan.self, from: Data(json.utf8))
        #expect(plan.effort == .high)
        #expect(plan.budgetUSD == 7.5)

        // Unknown effort falls back; a negative budget clamps to 0.
        let bad = #"{"name":"x","effort":"turbo","budgetUSD":-3}"#
        let plan2 = try JSONDecoder().decode(LoopPlan.self, from: Data(bad.utf8))
        #expect(plan2.effort == .medium)
        #expect(plan2.budgetUSD == 0)
    }

    // MARK: - Verifiable-goal warning (gap #5)

    @Test func vagueGoalWarnsButCheckableGoalDoesNot() {
        var plan = LoopPlan(name: "n", kind: .turnBased, goal: "make auth better")
        #expect(plan.validate().contains("loop.issue.vagueGoal"))

        // A goal a shell can check (test/pass/lint/number/`cmd`) does not warn.
        for good in ["all tests in tests/auth pass", "get coverage above 80%",
                     "`npm run build` succeeds", "the lint is clean"] {
            plan.goal = good
            #expect(!plan.validate().contains("loop.issue.vagueGoal"))
        }
    }

    // MARK: - Lifetime health (cost per accepted change)

    @Test func healthIsNilUntilTheLoopHasRun() {
        #expect(LoopPlan(name: "x").health == nil)
    }

    @Test func healthDerivesRateAndCostPerAccepted() {
        let plan = LoopPlan(name: "x", lifetimeRuns: 4, lifetimeAccepted: 3, lifetimeCostUSD: 6)
        let h = plan.health
        #expect(h?.acceptanceRate == 0.75)
        #expect(h?.costPerAccepted == 2)          // $6 over 3 accepted
        #expect(h?.isUnderperforming == false)    // 75% ≥ 50%
    }

    @Test func costPerAcceptedIsNilWhenNothingAccepted() {
        // Dividing $5 by zero accepted changes must NOT read as "free".
        let h = LoopPlan(name: "x", lifetimeRuns: 3, lifetimeAccepted: 0, lifetimeCostUSD: 5).health
        #expect(h?.costPerAccepted == nil)
        #expect(h?.isUnderperforming == true)     // 0% with enough data
    }

    @Test func underperformingNeedsEnoughData() {
        // One failed run isn't yet a verdict on the loop.
        let one = LoopPlan(name: "x", lifetimeRuns: 1, lifetimeAccepted: 0, lifetimeCostUSD: 1).health
        #expect(one?.hasEnoughData == false)
        #expect(one?.isUnderperforming == false)
    }

    @Test func healthCountersRoundTripAndClampNegative() throws {
        let json = #"{"name":"x","lifetimeRuns":5,"lifetimeAccepted":2,"lifetimeCostUSD":-9}"#
        let plan = try JSONDecoder().decode(LoopPlan.self, from: Data(json.utf8))
        #expect(plan.lifetimeRuns == 5)
        #expect(plan.lifetimeAccepted == 2)
        #expect(plan.lifetimeCostUSD == 0)        // negative clamps to 0

        // Absent keys default to zero (older saved plans).
        let old = try JSONDecoder().decode(LoopPlan.self, from: Data(#"{"name":"x"}"#.utf8))
        #expect(old.lifetimeRuns == 0)
        #expect(old.health == nil)
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
