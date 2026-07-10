//
//  ImportExportTests.swift
//  StrategyForgeTests
//
//  Round-trip tests: generate → parse (.claude/ import), export → import
//  (.sfstrategy), and the lint auto-fixer. All pure, no disk.
//

import Testing
import Foundation
@testable import StrategyForge

struct ClaudeConfigParserTests {

    /// Build the AgentFile inputs the parser expects from the generator output.
    private func agentFiles(for strategy: Strategy) -> [ClaudeConfigParser.AgentFile] {
        AgentFileGenerator.generate(for: strategy).map {
            .init(fileName: ($0.relativePath as NSString).lastPathComponent, contents: $0.contents)
        }
    }

    @Test func roundTripsFanoutCollapsingCounts() {
        let original = StrategyLibrary.orchestratorWorkers() // orchestrator + worker ×3
        let claudeMd = ClaudeMdGenerator.merged(existing: nil, strategy: original)
        let parsed = ClaudeConfigParser.parse(agentFiles: agentFiles(for: original),
                                              claudeMd: claudeMd, fallbackName: "repo")

        // Strategy name + orchestrator recovered from CLAUDE.md.
        #expect(parsed.name == original.name)
        #expect(parsed.orchestrator != nil)
        #expect(parsed.orchestrator?.model == original.orchestrator?.model)

        // worker-1..3 collapse back into one role with count 3.
        #expect(parsed.subagentRoles.count == 1)
        let worker = parsed.subagentRoles.first!
        #expect(worker.count == 3)
        #expect(worker.name == original.subagentRoles.first?.name)
        #expect(worker.model == original.subagentRoles.first?.model)
        #expect(worker.role == .worker)
    }

    @Test func recoversReadOnlyToolsAndKinds() {
        let original = StrategyLibrary.researchFanout() // researchers are read-only
        let claudeMd = ClaudeMdGenerator.merged(existing: nil, strategy: original)
        let parsed = ClaudeConfigParser.parse(agentFiles: agentFiles(for: original),
                                              claudeMd: claudeMd, fallbackName: "repo")
        let researcher = parsed.subagentRoles.first!
        #expect(researcher.role == .researcher)          // from the CLAUDE.md table
        #expect(researcher.tools.contains("Read"))       // tools survived frontmatter
        #expect(!researcher.tools.contains("Write"))
    }

    @Test func toleratesHandWrittenFileWithoutClaudeMd() {
        let file = ClaudeConfigParser.AgentFile(
            fileName: "helper.md",
            contents: """
            ---
            name: helper
            description: Use for chores
            model: claude-haiku-4-5
            ---

            You are a helper.
            """)
        let parsed = ClaudeConfigParser.parse(agentFiles: [file], claudeMd: nil, fallbackName: "my-repo")
        #expect(parsed.name == "my-repo")               // fallback name
        #expect(parsed.orchestrator != nil)             // synthesized
        #expect(parsed.subagentRoles.count == 1)
        #expect(parsed.subagentRoles.first?.model == .haiku45)
    }
}

struct StrategyPackageTests {

    @Test func exportImportRoundTrips() throws {
        let original = StrategyLibrary.plannerImplementersReviewer()
        let data = try StrategyPackage.export(original)
        let restored = try StrategyPackage.import(data)

        #expect(restored.name == original.name)
        #expect(restored.roles.count == original.roles.count)
        #expect(restored.roles.map(\.model) == original.roles.map(\.model))
        #expect(restored.roles.map(\.name) == original.roles.map(\.name))
        // Ids are regenerated so imports never collide.
        #expect(restored.id != original.id)
    }

    @Test func shareTextRoundTrips() throws {
        let original = StrategyLibrary.domainSpecialists()
        let text = try StrategyPackage.exportText(original)
        #expect(text.hasPrefix(StrategyPackage.textPrefix))
        let restored = try StrategyPackage.importText(text)
        #expect(restored.name == original.name)
        #expect(restored.roles.map(\.name) == original.roles.map(\.name))
        // Tolerates a raw base64 string without the prefix too.
        let raw = String(text.dropFirst(StrategyPackage.textPrefix.count))
        #expect((try? StrategyPackage.importText(raw))?.roles.count == original.roles.count)
    }

    @Test func importTextRejectsGarbage() {
        #expect((try? StrategyPackage.importText("not a share string!!")) == nil)
    }
}

struct AutoFixTests {

    @Test func stripsWriteToolsFromReviewerAndAgentFromWorker() {
        var s = StrategyLibrary.orchestratorWorkers()
        // Corrupt: give a worker the Agent tool, and add a reviewer with Write.
        s.roles[1].tools = ["Write", "Agent"]
        s.roles.append(AgentRole(name: "reviewer", role: .reviewer, model: .sonnet5,
                                 systemPrompt: "review", description: "reviews",
                                 tools: ["Read", "Edit"]))
        #expect(s.hasAutoFixableIssues)

        let fixed = s.autoFixed()
        let worker = fixed.roles[1]
        #expect(!worker.tools.contains("Agent"))         // single level of delegation
        let reviewer = fixed.roles.first { $0.role == .reviewer }!
        #expect(!reviewer.tools.contains("Edit"))        // read-only enforced
        #expect(reviewer.tools.contains("Read"))
        #expect(!fixed.hasAutoFixableIssues)             // idempotent
    }

    @Test func deduplicatesNames() {
        var s = StrategyLibrary.orchestratorWorkers()
        s.roles[1].name = "dup"
        s.roles.append(AgentRole(name: "dup", role: .worker, model: .sonnet5,
                                 systemPrompt: "x", description: "y"))
        let fixed = s.autoFixed()
        let names = fixed.roles.map(\.name)
        #expect(Set(names).count == names.count)         // all unique now
    }
}

struct StrategyGeneratorTests {

    private let allShapes: [StrategyShape] = [
        .solo, .executorAdvisor, .plannerReviewer, .orchestratorWorkers,
        .researchFanout, .debateConsensus, .domainSpecialists, .sparring,
    ]

    @Test func everyShapeBuildsAValidStrategy() {
        for shape in allShapes {
            let s = StrategyGenerator.buildStrategy(shape: shape, teamSize: 4)
            #expect(s.isValid, "\(shape) should build a valid strategy")
        }
    }

    @Test func teamSizeScalesTheFanoutRole() {
        let s = StrategyGenerator.buildStrategy(shape: .orchestratorWorkers, teamSize: 5)
        let maxCount = s.subagentRoles.map(\.count).max() ?? 0
        #expect(maxCount == 5)
    }

    @Test func teamSizeIsClampedAndSoloIgnoresIt() {
        // Out-of-range size is clamped; solo has no fan-out role to scale.
        let solo = StrategyGenerator.buildStrategy(shape: .solo, teamSize: 99)
        #expect(solo.isValid)
        #expect(solo.subagentRoles.isEmpty)
    }

    @Test func heuristicMapsKeywords() {
        #expect(StrategyGenerator.heuristicShape(for: "help me understand this unfamiliar codebase").0 == .researchFanout)
        #expect(StrategyGenerator.heuristicShape(for: "just a quick experiment").0 == .solo)
        #expect(StrategyGenerator.heuristicShape(for: "rename this symbol across all files").0 == .orchestratorWorkers)
        #expect(StrategyGenerator.heuristicShape(for: "fix the login bug").0 == .executorAdvisor) // default
    }
}
