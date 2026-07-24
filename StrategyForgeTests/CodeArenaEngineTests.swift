//
//  CodeArenaEngineTests.swift
//  StrategyForgeTests
//
//  The write-capable arena, against a REAL temp git repo: each contestant edits inside
//  its own worktree (the user's tree stays clean), the diff is captured, applying a
//  winner merges exactly one branch back, and cleanup leaves nothing behind.
//

import Testing
import Foundation
@testable import Coral

/// A write-capable fake runner: writes a per-provider file into the given cwd (the
/// worktree), so we can assert isolation + diff capture without a real CLI.
private struct WritingRunner: OneShotRunner {
    var failing: Set<AIProvider> = []
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        if failing.contains(provider) { throw OneShotError.failed("\(provider.displayName) down") }
        if let cwd {
            let file = URL(fileURLWithPath: cwd).appendingPathComponent("\(provider.rawValue).txt")
            try? "edit by \(provider.displayName)\n".write(to: file, atomically: true, encoding: .utf8)
        }
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

struct CodeArenaEngineTests {

    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coral-codearena-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: dir)
        try "seed\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: dir)
        try git(["commit", "-q", "-m", "base"], in: dir)
        return dir
    }

    private func changedFileCount(in dir: URL) throws -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.currentDirectoryURL = dir
        p.arguments = ["status", "--porcelain"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").count
    }

    private let entrants = [
        ArenaEntrant(provider: .claude, model: "opus"),
        ArenaEntrant(provider: .openai, model: "gpt-5"),
    ]

    @Test func eachContestantEditsInIsolationAndTheUserTreeStaysClean() async throws {
        guard CodeGit.isAvailable else { return }
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let finals = await CodeArenaEngine.run(
            task: "add a file", repo: repo.path, entrants: entrants, runner: WritingRunner()) { _, _ in }

        #expect(finals.count == 2)
        #expect(finals.values.allSatisfy { $0.state == .done })
        #expect(finals["claude:opus"]?.diff.contains("claude.txt") == true)
        #expect(finals["openai:gpt-5"]?.diff.contains("openai.txt") == true)
        #expect(finals["claude:opus"]?.producedChanges == true)
        // The user's working tree was never touched — still clean.
        #expect(try changedFileCount(in: repo) == 0)

        await CodeArenaEngine.cleanup(repo: repo.path, all: Array(finals.values))
    }

    @Test func applyingAWinnerMergesExactlyThatWorkIntoTheUserTree() async throws {
        guard CodeGit.isAvailable else { return }
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let finals = await CodeArenaEngine.run(
            task: "add a file", repo: repo.path, entrants: entrants, runner: WritingRunner()) { _, _ in }
        let winner = try #require(finals["openai:gpt-5"])

        let merge = await CodeArenaEngine.applyWinner(repo: repo.path, winner: winner, all: Array(finals.values))
        #expect(merge.ok)
        // The winner's file is now in the user's tree; the loser's is NOT.
        #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("openai.txt").path))
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("claude.txt").path))
        // Worktrees are gone (nothing left under the arena root for these branches).
        #expect(!FileManager.default.fileExists(atPath: winner.worktreePath))
    }

    @Test func aFailingContestantDoesNotSinkTheArena() async throws {
        guard CodeGit.isAvailable else { return }
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let finals = await CodeArenaEngine.run(
            task: "x", repo: repo.path, entrants: entrants,
            runner: WritingRunner(failing: [.openai])) { _, _ in }
        #expect(finals["openai:gpt-5"]?.state == .failed)
        #expect(finals["claude:opus"]?.state == .done)
        #expect(try changedFileCount(in: repo) == 0)   // still clean
        await CodeArenaEngine.cleanup(repo: repo.path, all: Array(finals.values))
    }
}
