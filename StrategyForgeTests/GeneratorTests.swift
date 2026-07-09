//
//  GeneratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the pure generators: valid frontmatter, count expansion, and
//  CLAUDE.md idempotency.
//

import Testing
import Foundation
@testable import StrategyForge

struct AgentFileGeneratorTests {

    @Test func skipsOrchestratorAndExpandsCount() {
        let strategy = StrategyLibrary.orchestratorWorkers() // 1 orchestrator + 3 workers
        let files = AgentFileGenerator.generate(for: strategy)

        // Orchestrator produces no file.
        #expect(files.allSatisfy { !$0.relativePath.contains("orchestrator") })
        // Three worker files, suffixed.
        #expect(files.count == 3)
        let paths = Set(files.map(\.relativePath))
        #expect(paths.contains(".claude/agents/worker-1.md"))
        #expect(paths.contains(".claude/agents/worker-2.md"))
        #expect(paths.contains(".claude/agents/worker-3.md"))
    }

    @Test func singleInstanceHasNoSuffix() {
        let strategy = StrategyLibrary.executorAdvisor() // advisor count 1
        let files = AgentFileGenerator.generate(for: strategy)
        #expect(files.count == 1)
        #expect(files.first?.relativePath == ".claude/agents/advisor.md")
    }

    @Test func frontmatterIsValidAndPinsModel() {
        let strategy = StrategyLibrary.orchestratorWorkers()
        let file = AgentFileGenerator.generate(for: strategy).first!
        let contents = file.contents

        // Well-formed frontmatter fences.
        #expect(contents.hasPrefix("---\n"))
        let fenceCount = contents.components(separatedBy: "---").count - 1
        #expect(fenceCount == 2)

        // Required keys present.
        #expect(contents.contains("name: worker-1"))
        #expect(contents.contains("description:"))
        #expect(contents.contains("model: claude-sonnet-5"))

        // Workers inherit all tools → no `tools:` line.
        #expect(!contents.contains("tools:"))

        // Body follows the frontmatter.
        #expect(contents.contains("You are a worker"))
    }

    @Test func toolsAreEmittedWhenPresent() {
        let strategy = StrategyLibrary.researchFanout() // researchers are read-only
        let file = AgentFileGenerator.generate(for: strategy).first!
        #expect(file.contents.contains("tools: Read, Grep, Glob"))
    }

    @Test func descriptionWithColonIsQuoted() {
        var role = AgentRole(
            name: "x",
            role: .worker,
            model: .sonnet5,
            systemPrompt: "body",
            description: "Use this: after building"
        )
        role.tools = []
        let md = AgentFileGenerator.markdown(for: role, instanceName: "x")
        #expect(md.contains("description: \"Use this: after building\""))
    }
}

struct ClaudeMdGeneratorTests {

    @Test func createsFromScratchWithMarkers() {
        let strategy = StrategyLibrary.orchestratorWorkers()
        let out = ClaudeMdGenerator.merged(existing: nil, strategy: strategy)
        #expect(out.contains(ClaudeMdGenerator.startMarker))
        #expect(out.contains(ClaudeMdGenerator.endMarker))
        #expect(out.contains("Orchestrator + Workers"))
        // Documents launch model, not frontmatter.
        #expect(out.contains("claude --model claude-fable-5"))
        // Subagent table row.
        #expect(out.contains("`worker-1`"))
    }

    @Test func preservesUserContentWhenAppending() {
        let strategy = StrategyLibrary.solo()
        let existing = "# My project\n\nSome important notes.\n"
        let out = ClaudeMdGenerator.merged(existing: existing, strategy: strategy)
        #expect(out.contains("# My project"))
        #expect(out.contains("Some important notes."))
        #expect(out.contains(ClaudeMdGenerator.startMarker))
    }

    @Test func isIdempotent() {
        let strategy = StrategyLibrary.plannerImplementersReviewer()
        let existing = "# Keep me\n"
        let once = ClaudeMdGenerator.merged(existing: existing, strategy: strategy)
        let twice = ClaudeMdGenerator.merged(existing: once, strategy: strategy)
        #expect(once == twice)
        // Exactly one managed block after repeated merges.
        let markerCount = twice.components(separatedBy: ClaudeMdGenerator.startMarker).count - 1
        #expect(markerCount == 1)
    }

    @Test func replacesStaleSectionOnStrategyChange() {
        let first = ClaudeMdGenerator.merged(existing: "# Repo\n",
                                             strategy: StrategyLibrary.solo())
        #expect(first.contains("Solo (baseline)"))
        let second = ClaudeMdGenerator.merged(existing: first,
                                              strategy: StrategyLibrary.researchFanout())
        #expect(second.contains("Research Fan-out"))
        #expect(!second.contains("Solo (baseline)"))
        #expect(second.contains("# Repo")) // user content preserved
    }
}

struct LaunchCommandGeneratorTests {

    @Test func usesOrchestratorModel() {
        let strategy = StrategyLibrary.debateConsensus() // moderator is Opus 4.8
        #expect(LaunchCommandGenerator.command(for: strategy) == "claude --model claude-opus-4-8")
        #expect(LaunchCommandGenerator.inSessionInstruction(for: strategy) == "/model claude-opus-4-8")
    }

    @Test func respectsCustomBinaryPath() {
        let strategy = StrategyLibrary.solo()
        let cmd = LaunchCommandGenerator.command(for: strategy, binary: "/usr/local/bin/claude")
        #expect(cmd.hasPrefix("/usr/local/bin/claude --model "))
    }

    @Test func gitCommitCommandStagesConfigFiles() {
        let cmd = LaunchCommandGenerator.gitCommitCommand()
        #expect(cmd.contains("git add .claude CLAUDE.md"))
        #expect(cmd.contains("git commit -m"))
    }
}

struct CostEstimatorTests {

    @Test func soloCostsLessThanABigTeam() {
        let solo = CostEstimator.estimate(StrategyLibrary.solo())
        let domain = CostEstimator.estimate(StrategyLibrary.domainSpecialists())
        #expect(solo.perRun < domain.perRun)
        #expect(solo.perRun > 0)
    }

    @Test func moreInstancesCostMore() {
        var s = StrategyLibrary.orchestratorWorkers()
        let base = CostEstimator.estimate(s).perRun
        if let i = s.roles.firstIndex(where: { !$0.isOrchestrator }) {
            s.roles[i].count += 3
        }
        #expect(CostEstimator.estimate(s).perRun > base)
    }

    @Test func breakdownCoversUsedModels() {
        let cost = CostEstimator.estimate(StrategyLibrary.orchestratorWorkers())
        // Fan-out uses Fable (orchestrator) + Sonnet (workers).
        #expect(cost.byModel[.fable5] != nil)
        #expect(cost.byModel[.sonnet5] != nil)
    }

    @Test func effortScalesCostAndMediumIsBaseline() {
        let s = StrategyLibrary.orchestratorWorkers()
        let low = CostEstimator.estimate(s, effort: .low).perRun
        let medium = CostEstimator.estimate(s, effort: .medium).perRun
        let high = CostEstimator.estimate(s, effort: .high).perRun
        #expect(low < medium)
        #expect(high > medium)
        // The no-effort overload must equal the medium baseline (keeps other tests
        // and per-strategy tier pills stable).
        #expect(CostEstimator.estimate(s).perRun == medium)
    }
}

struct StrategyValidationTests {

    @Test func templatesAreAllValid() {
        for strategy in StrategyLibrary.all {
            #expect(strategy.isValid, "Template \(strategy.name) should be valid")
        }
    }

    @Test func detectsMissingOrchestrator() {
        var strategy = StrategyLibrary.orchestratorWorkers()
        strategy.roles = strategy.roles.filter { !$0.isOrchestrator }
        #expect(!strategy.isValid)
    }

    @Test func detectsDuplicateNames() {
        var strategy = StrategyLibrary.orchestratorWorkers()
        strategy.roles[1].name = strategy.roles[0].name
        #expect(!strategy.isValid)
    }
}

struct StrategyWriterTests {

    /// Round-trips a real write to a temp dir and checks the file layout.
    @Test func writesAgentsAndClaudeMd() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sf-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let writer = StrategyWriter(repoURL: tmp)
        let strategy = StrategyLibrary.orchestratorWorkers()
        let written = try writer.write(strategy: strategy)

        #expect(written.contains(".claude/agents/worker-1.md"))
        #expect(written.contains("CLAUDE.md"))

        let workerURL = tmp.appendingPathComponent(".claude/agents/worker-1.md")
        let worker = try String(contentsOf: workerURL, encoding: .utf8)
        #expect(worker.contains("model: claude-sonnet-5"))

        // Second write preserves surrounding CLAUDE.md content and stays idempotent.
        let claudeURL = tmp.appendingPathComponent("CLAUDE.md")
        var body = try String(contentsOf: claudeURL, encoding: .utf8)
        body = "# User header\n\n" + body
        try body.write(to: claudeURL, atomically: true, encoding: .utf8)
        try writer.write(strategy: strategy)
        let after = try String(contentsOf: claudeURL, encoding: .utf8)
        #expect(after.contains("# User header"))
        let markerCount = after.components(separatedBy: ClaudeMdGenerator.startMarker).count - 1
        #expect(markerCount == 1)
    }
}
