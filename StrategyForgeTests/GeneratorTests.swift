//
//  GeneratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the pure generators: valid frontmatter, count expansion, and
//  CLAUDE.md idempotency.
//

import Testing
import Foundation
@testable import Coral

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

    @Test func memoryOffEmitsNoMemorySectionOrSeed() {
        let role = AgentRole(name: "w", role: .worker, model: .sonnet5,
                             systemPrompt: "body", description: "d")
        let md = AgentFileGenerator.markdown(for: role, instanceName: "w")
        #expect(!md.contains("## Memory"))
        let strategy = Strategy(name: "T", description: "", roles: [role], orchestrationNotes: "")
        #expect(AgentFileGenerator.memorySeedFiles(for: strategy).isEmpty)
    }

    @Test func memoryOnAddsSectionPointingAtItsFile() {
        var role = AgentRole(name: "w", role: .worker, model: .sonnet5,
                             systemPrompt: "body", description: "d")
        role.memoryEnabled = true
        let md = AgentFileGenerator.markdown(for: role, instanceName: "w")
        #expect(md.contains("## Memory"))
        #expect(md.contains(".claude/memory/w.md"))
    }

    @Test func memorySeedIsOnePerExpandedInstance() {
        var role = AgentRole(name: "w", role: .worker, model: .sonnet5,
                             systemPrompt: "body", description: "d", count: 3)
        role.memoryEnabled = true
        let strategy = Strategy(name: "T", description: "", roles: [role], orchestrationNotes: "")
        let seeds = AgentFileGenerator.memorySeedFiles(for: strategy)
        #expect(seeds.map(\.relativePath).sorted() == [
            ".claude/memory/w-1.md", ".claude/memory/w-2.md", ".claude/memory/w-3.md"])
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

    @Test func includesDelegationPlaybookForTeams() {
        let strategy = StrategyLibrary.orchestratorWorkers()
        let out = ClaudeMdGenerator.merged(existing: nil, strategy: strategy)
        // The "manager, not micromanager" habits guide HOW the lead delegates.
        #expect(out.contains("Delegate like a manager, not a micromanager"))
        #expect(out.contains("Delegate early, not late"))
        #expect(out.contains("Review the diff; don't rewrite it"))
    }

    @Test func soloHasNoDelegationPlaybook() {
        // A solo config has nothing to delegate, so the playbook is omitted.
        let out = ClaudeMdGenerator.merged(existing: nil, strategy: StrategyLibrary.solo())
        #expect(!out.contains("Delegate like a manager"))
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

    @Test func disorderedMarkersDoNotCrash() {
        // End marker before start (corrupted/injected) must NOT crash on an invalid
        // Range — it should ignore the markers and append a fresh managed block.
        let corrupted = "\(ClaudeMdGenerator.endMarker)\nstray\n\(ClaudeMdGenerator.startMarker)\n"
        let out = ClaudeMdGenerator.merged(existing: corrupted, strategy: StrategyLibrary.solo())
        #expect(out.contains("Solo (baseline)"))
        #expect(out.hasPrefix(ClaudeMdGenerator.endMarker) || out.contains("stray"))
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

struct MissionReportTests {
    @Test func headlineReadsLikeAShareableBrag() {
        #expect(MissionReport.headline(agentCount: 4, costUSD: 0.83, tokens: 1000) == "A 4-agent team finished for $0.83.")
        #expect(MissionReport.headline(agentCount: 1, costUSD: 0, tokens: 12_000).contains("single agent"))
    }

    @Test func markdownIncludesTeamAgentsAndOutcome() {
        let strategy = StrategyLibrary.orchestratorWorkers()
        let lines = MissionReport.agentLines(strategy: strategy, timeline: [])
        let md = MissionReport.markdown(title: "Improve the HUD", strategyName: "Orchestrator + Workers",
                                        agents: lines, tokens: 24_500, costUSD: 0.83,
                                        elapsed: "2m 10s", outcome: "Reworked the HUD tokens.")
        #expect(md.contains("# Mission report — Improve the HUD"))
        #expect(md.contains("finished for $0.83"))
        #expect(md.contains("| Agent | Role | Model | Steps | Time |"))
        #expect(md.contains("## Outcome"))
        #expect(md.contains("Reworked the HUD tokens."))
        #expect(lines.count == strategy.roles.count)   // one line per role
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

    @Test func cheaperModelCostsLess() {
        // Same single-agent shape, cheaper model → strictly cheaper: Solo · Economy runs
        // on Haiku, the Solo baseline on Opus. This is a guaranteed ordering, unlike
        // solo-vs-team, which depends on the team's token/model mix and can tie (a big
        // team of cheap workers costs about the same as one frontier-model agent).
        let economy = CostEstimator.estimate(StrategyLibrary.soloEconomy())
        let solo = CostEstimator.estimate(StrategyLibrary.solo())
        #expect(economy.perRun < solo.perRun)
        #expect(economy.perRun > 0)
    }

    @Test func moreInstancesCostMore() {
        var s = StrategyLibrary.orchestratorWorkers()
        let base = CostEstimator.estimate(s).perRun
        if let i = s.roles.firstIndex(where: { !$0.isOrchestrator }) {
            s.roles[i].count += 3
        }
        #expect(CostEstimator.estimate(s).perRun > base)
    }

    @Test func soloLeadCostsMoreThanTheSameLeadDelegating() {
        // Per the delegation economics, the lead's own token bill tracks how much it
        // hands off. A solo lead does the work itself; give it a team and its own
        // contribution drops. Isolate the LEAD's cost with a different-model worker
        // (Haiku) so `byModel[.opus48]` is purely the Opus lead's share.
        let solo = StrategyLibrary.solo()               // single Opus agent, no team
        let soloLead = CostEstimator.estimate(solo).byModel[.opus48] ?? 0

        var team = solo
        team.roles.append(AgentRole(name: "worker", role: .worker, model: .haiku45,
                                    systemPrompt: "implement", description: "do the work"))
        let delegatingLead = CostEstimator.estimate(team).byModel[.opus48] ?? 0

        #expect(soloLead > 0)
        #expect(delegatingLead < soloLead)
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

    @Test func effectiveCostBreakdownSumsToTotal() {
        // The effective-cost model (tokenizer overhead + cache-read discount) must
        // stay internally consistent: the per-model breakdown sums to perRun.
        let cost = CostEstimator.estimate(StrategyLibrary.domainSpecialists())
        let sum = cost.byModel.values.reduce(0, +)
        #expect(cost.perRun > 0)
        #expect(abs(sum - cost.perRun) < 0.0001)
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

    @Test func detectsExpandedNameCollision() {
        // A "worker" with count 3 writes worker-1…worker-3; a literal "worker-1" writes
        // the same file — different names, so the plain duplicate check misses it.
        var strategy = StrategyLibrary.orchestratorWorkers()
        let orch = strategy.roles.first { $0.isOrchestrator }!
        strategy.roles = [orch,
                          AgentRole(name: "worker", role: .worker, model: .haiku45,
                                    systemPrompt: "", description: "", count: 3),
                          AgentRole(name: "worker-1", role: .worker, model: .haiku45,
                                    systemPrompt: "", description: "", count: 1)]
        #expect(!strategy.isValid)
        #expect(strategy.validate().contains { $0.message.contains("worker-1.md") })
    }
}

struct ClaudeMdMarkerTests {
    @Test func neutralizesInjectedEndMarker() {
        // A name/description carrying the end marker must not survive into the section
        // body (it would prematurely close the managed block on the next merge).
        var s = StrategyLibrary.solo()
        s.description = "Sneaky <!-- CORAL:END --> injection"
        let section = ClaudeMdGenerator.section(for: s)
        #expect(!section.contains(ClaudeMdGenerator.endMarker))
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

struct WorkflowGeneratorTests {

    @Test func teamProducesRunnableWorkflowWithPhasesAndParallel() {
        let strategy = StrategyLibrary.orchestratorWorkers()   // orchestrator + 3 workers
        let js = WorkflowGenerator.workflow(for: strategy)!
        // Valid dynamic-workflow shape.
        #expect(js.contains("export const meta = {"))
        #expect(js.contains("phases: [{ title: 'Plan' }, { title: 'Work' }, { title: 'Synthesize' }]"))
        #expect(js.contains("phase('Plan')"))
        #expect(js.contains("await parallel(["))
        #expect(js.contains("return final"))
        // One agent() branch per teammate.
        let branches = js.components(separatedBy: "() => agent(").count - 1
        #expect(branches == strategy.subagentRoles.count)
        // Pins each teammate's model.
        #expect(js.contains("model: 'claude-fable-5'") || js.contains("model: 'claude-sonnet-5'"))
        // The task is read from args.
        #expect(js.contains("typeof args === 'string'"))
    }

    @Test func soloTeamHasNoWorkflow() {
        #expect(WorkflowGenerator.workflow(for: StrategyLibrary.solo()) == nil)
    }

    @Test func fileNameSlugIsFilesystemSafe() {
        var s = StrategyLibrary.solo()
        s.name = "My Team / v2!"
        #expect(WorkflowGenerator.fileName(for: s) == ".claude/workflows/my-team-v2.mjs")
    }

    @Test func personaBackticksCannotBreakOutOfTheTemplate() {
        var s = StrategyLibrary.orchestratorWorkers()
        s.roles[1].systemPrompt = "do `x` and ${danger}"
        let js = WorkflowGenerator.workflow(for: s)!
        // The backtick and ${ are escaped so they can't terminate/interpolate the literal.
        #expect(js.contains("do \\`x\\` and \\${danger}"))
    }
}
