//
//  CrossProviderEditorTests.swift
//  StrategyForgeTests
//
//  Cross-provider sequential editing with per-line provenance, against a real temp repo:
//  two providers edit the same file in sequence, and each line ends up credited to the
//  provider that wrote it.
//

import Testing
import Foundation
@testable import Coral

/// A fake runner where each provider APPENDS a provider-tagged line to shared.txt — so
/// after both run, the file has one line per provider and we can check line authorship.
private struct SequentialEditRunner: OneShotRunner {
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        guard let cwd else { return OneShotResult(text: "", tokens: 1, costUSD: 0, provider: provider, model: model) }
        let url = URL(fileURLWithPath: cwd).appendingPathComponent("shared.txt")
        var contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !contents.isEmpty, !contents.hasSuffix("\n") { contents += "\n" }
        contents += "line by \(provider.rawValue)\n"
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return OneShotResult(text: "done", tokens: 10, costUSD: 0.01, provider: provider, model: model)
    }
}

private func git(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.currentDirectoryURL = dir
    p.arguments = ["-c", "user.name=t", "-c", "user.email=t@t.t", "-c", "commit.gpgsign=false"] + args
    p.standardOutput = Pipe(); p.standardError = Pipe()
    try p.run(); p.waitUntilExit()
}

struct CrossProviderEditorTests {

    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coral-xprov-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: dir)
        try "seed\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: dir)
        try git(["commit", "-q", "-m", "base"], in: dir)
        return dir
    }

    /// A two-role team: a Gemini worker then an OpenAI worker, editing the same file.
    private func mixedTeam() -> Strategy {
        var s = StrategyLibrary.domainSpecialists()   // several DISTINCT subagent roles
        // Reassign two subagents to distinct non-Claude providers.
        var reassigned = 0
        for i in s.roles.indices where !s.roles[i].isOrchestrator {
            s.roles[i].provider = (reassigned == 0) ? .gemini : .openai
            reassigned += 1
            if reassigned == 2 { break }
        }
        // Keep exactly two subagents so the sequence is deterministic.
        var kept = 0
        s.roles = s.roles.filter { role in
            if role.isOrchestrator { return true }
            kept += 1; return kept <= 2
        }
        return s
    }

    @Test func detectsCrossProviderTeams() {
        #expect(CrossProviderEditor.isCrossProvider(mixedTeam()))
        #expect(!CrossProviderEditor.isCrossProvider(StrategyLibrary.solo()))   // all Claude
    }

    @Test func sequentialEditsAttributeEachLineToItsProvider() async throws {
        guard CodeGit.isAvailable else { return }
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        var workerProviders: [AIProvider] = []
        let result = await CrossProviderEditor.run(
            task: "append your line", worktree: repo.path, strategy: mixedTeam(),
            runner: SequentialEditRunner()) { prov in workerProviders.append(prov.provider) }

        // Both providers ran, in order.
        #expect(workerProviders == [.gemini, .openai])
        #expect(result.error == nil)
        #expect(result.diff.contains("shared.txt"))

        // shared.txt was touched by BOTH providers.
        let file = try #require(result.perFile.first { $0.file == "shared.txt" })
        #expect(Set(file.authors.map(\.provider)) == [.gemini, .openai])

        // Per-line authorship: the gemini line is credited to gemini, the openai line to openai.
        let authors = try #require(result.lineAuthors["shared.txt"])
        // The file is "line by gemini\nline by openai\n" → lines[0]=gemini, lines[1]=openai.
        #expect(authors.count >= 2)
        #expect(authors[0]?.provider == .gemini)
        #expect(authors[1]?.provider == .openai)
    }
}
