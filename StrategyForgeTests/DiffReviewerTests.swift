//
//  DiffReviewerTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for the automated diff reviewer (prompt, tolerant parse, severity
//  ordering, blocking gate) + a review() integration driven by a mock OneShotRunner.
//

import Testing
import Foundation
@testable import Coral

struct DiffReviewerParsingTests {

    @Test func parsesFindingsTolerantlyAndSortsHighFirst() {
        let text = """
        Here's the review:
        [
          {"severity":"low","title":"minor","detail":"d1","file":"a.swift","line":3},
          {"severity":"high","title":"nil crash","detail":"unwrap can crash","file":"b.swift","line":"42"},
          {"nope":"malformed"},
          {"severity":"weird","title":"unknown sev","detail":"","file":""}
        ]
        """
        let findings = DiffReviewer.parseFindings(text)
        #expect(findings.count == 3)                       // malformed dropped
        #expect(findings.first?.severity == .high)         // sorted high-first
        #expect(findings.first?.line == 42)                // numeric string parsed
        #expect(findings[1].severity == .medium)           // unknown severity → medium (sorts to middle)
        #expect(findings.last?.severity == .low)           // low sorts last
    }

    @Test func emptyArrayAndGarbageYieldNoFindings() {
        #expect(DiffReviewer.parseFindings("[]").isEmpty)
        #expect(DiffReviewer.parseFindings("the diff looks fine").isEmpty)
    }

    @Test func blockingAndCleanGates() {
        let clean = DiffReview(findings: [])
        #expect(clean.isClean)
        #expect(!clean.hasBlocking)
        // A reviewer failure is NOT a clean review, even with zero findings.
        #expect(!DiffReview(findings: [], error: "CLI not installed").isClean)
        let high = DiffReview(findings: [ReviewFinding(severity: .high, title: "t", detail: "", file: "")])
        #expect(high.hasBlocking)
        let mediumOnly = DiffReview(findings: [ReviewFinding(severity: .medium, title: "t", detail: "", file: "")])
        #expect(!mediumOnly.hasBlocking)
        #expect(!mediumOnly.isClean)
    }

    @Test func promptCarriesTheDiff() {
        let p = DiffReviewer.reviewPrompt(diff: "@@ -1 +1 @@\n-old\n+new")
        #expect(p.contains("INDEPENDENT code reviewer"))
        #expect(p.contains("+new"))
        #expect(p.contains("JSON array"))
    }
}

/// Returns a fixed reply regardless of input.
private struct FixedRunner: OneShotRunner {
    let reply: String
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        OneShotResult(text: reply, tokens: 0, costUSD: 0, provider: provider, model: model)
    }
}

/// Always throws — a reviewer CLI that failed to launch.
private struct FailingRunner: OneShotRunner {
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        throw OneShotError.failed("claude exited with code 1")
    }
}

struct DiffReviewIntegrationTests {

    @Test func emptyDiffIsCleanWithoutCallingTheModel() async {
        let review = await DiffReviewer.review(diff: "   \n  ", runner: FixedRunner(reply: "should not be used"))
        #expect(review.isClean)
    }

    @Test func reviewParsesTheRunnerVerdict() async {
        let reply = #"[{"severity":"high","title":"off by one","detail":"loop overruns","file":"x.swift","line":10}]"#
        let review = await DiffReviewer.review(diff: "@@ real diff @@", runner: FixedRunner(reply: reply))
        #expect(review.findings.count == 1)
        #expect(review.hasBlocking)
        #expect(review.findings.first?.title == "off by one")
    }

    @Test func runnerFailureSurfacesAnErrorNotACleanReview() async {
        let review = await DiffReviewer.review(diff: "@@ real diff @@", runner: FailingRunner())
        #expect(review.error == "claude exited with code 1")
        #expect(!review.isClean)
        #expect(review.findings.isEmpty)
    }
}

// MARK: - fullDiff (the reviewer's input)

/// Run real git in `dir` for repo-fixture setup (macOS test runners always have git;
/// `-c` overrides keep commits independent of the machine's git config).
private func gitFixture(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.currentDirectoryURL = dir
    p.arguments = ["-c", "user.name=t", "-c", "user.email=t@t.t", "-c", "commit.gpgsign=false"] + args
    p.standardOutput = Pipe(); p.standardError = Pipe()
    try p.run()
    p.waitUntilExit()
}

/// CodeGit.fullDiff feeds the independent reviewer, which gates a commit that runs
/// `git add -A` — so it must include untracked (never-staged) files, the typical form
/// of agent-generated work, not just `git diff HEAD`.
struct CodeGitFullDiffTests {

    private func makeTempRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-fulldiff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try gitFixture(["init", "-q"], in: dir)
        return dir
    }

    @Test func untrackedFilesAppearEvenOnAnUnbornHEAD() async throws {
        guard CodeGit.isAvailable else { return }
        let dir = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Unborn HEAD + only an untracked file: `git diff HEAD` alone reports nothing —
        // the old false-clean blind spot.
        try "let answer = 42\n".write(to: dir.appendingPathComponent("New.swift"),
                                      atomically: true, encoding: .utf8)
        let diff = await CodeGit.fullDiff(repo: dir.path)
        let out = try #require(diff)
        #expect(out.contains("New.swift"))
        #expect(out.contains("+let answer = 42"))
    }

    @Test func combinesTrackedAndUntrackedChanges() async throws {
        guard CodeGit.isAvailable else { return }
        let dir = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "old\n".write(to: dir.appendingPathComponent("Tracked.txt"),
                          atomically: true, encoding: .utf8)
        try gitFixture(["add", "."], in: dir)
        try gitFixture(["commit", "-q", "-m", "base"], in: dir)
        try "new\n".write(to: dir.appendingPathComponent("Tracked.txt"),
                          atomically: true, encoding: .utf8)
        try "brand new\n".write(to: dir.appendingPathComponent("Untracked.txt"),
                                atomically: true, encoding: .utf8)
        let diff = await CodeGit.fullDiff(repo: dir.path)
        let out = try #require(diff)
        #expect(out.contains("-old"))
        #expect(out.contains("+new"))
        #expect(out.contains("Untracked.txt"))
        #expect(out.contains("+brand new"))
    }

    @Test func cleanRepoStillYieldsNil() async throws {
        guard CodeGit.isAvailable else { return }
        let dir = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "same\n".write(to: dir.appendingPathComponent("A.txt"),
                           atomically: true, encoding: .utf8)
        try gitFixture(["add", "."], in: dir)
        try gitFixture(["commit", "-q", "-m", "base"], in: dir)
        let diff = await CodeGit.fullDiff(repo: dir.path)
        #expect(diff == nil)
    }
}
