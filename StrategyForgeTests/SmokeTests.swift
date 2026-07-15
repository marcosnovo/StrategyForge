//
//  SmokeTests.swift
//  StrategyForgeTests
//
//  Phase 5 smoke test: generate the "Orchestrator + Workers" strategy into a
//  throwaway repo and verify the .md files have valid frontmatter and the
//  CLAUDE.md is coherent.
//

import Testing
import Foundation
@testable import Coral

struct SmokeTests {

    @Test func orchestratorWorkersEndToEnd() throws {
        // 1. A throwaway "repo".
        let repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sf-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        // 2. Generate.
        let strategy = StrategyLibrary.orchestratorWorkers()
        let writer = StrategyWriter(repoURL: repo, binary: "claude")
        try writer.write(strategy: strategy)

        // 3. Agent files exist with valid frontmatter and pinned model.
        let agentsDir = repo.appendingPathComponent(".claude/agents")
        let agentFiles = try FileManager.default.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        #expect(agentFiles.count == 3, "3 workers expected")

        for file in agentFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let (frontmatter, body) = try splitFrontmatter(contents)
            #expect(frontmatter["name"] != nil)
            #expect(frontmatter["description"]?.isEmpty == false)
            #expect(frontmatter["model"] == "claude-sonnet-5")
            // No orchestrator file leaked in.
            #expect(frontmatter["name"]?.hasPrefix("worker") == true)
            #expect(!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        // 4. CLAUDE.md is coherent.
        let claude = try String(contentsOf: repo.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        #expect(claude.contains("Orchestrator + Workers"))
        #expect(claude.contains("claude --model claude-fable-5"))     // launch model, not frontmatter
        #expect(claude.contains("Single level of delegation"))
        #expect(claude.contains("`worker-1`"))
        #expect(claude.contains(ClaudeMdGenerator.startMarker))
        #expect(claude.contains(ClaudeMdGenerator.endMarker))
    }

    /// Minimal frontmatter parser: expects `---\n<key: value>*\n---\n<body>`.
    private func splitFrontmatter(_ text: String) throws -> (fields: [String: String], body: String) {
        let lines = text.components(separatedBy: "\n")
        try #require(lines.first == "---")
        var fields: [String: String] = [:]
        var index = 1
        while index < lines.count, lines[index] != "---" {
            let line = lines[index]
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                fields[key] = value
            }
            index += 1
        }
        try #require(index < lines.count, "closing frontmatter fence missing")
        let body = lines[(index + 1)...].joined(separator: "\n")
        return (fields, body)
    }
}
