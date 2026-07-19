//
//  MetaOrchestratorTests.swift
//  StrategyForgeTests
//
//  Unit tests for the Level 2 cross-provider engine: pure plan parsing / model
//  resolution, and the full Plan → Delegate → Synthesize loop driven by a mock
//  runner (so no CLIs are spawned).
//

import Testing
import Foundation
@testable import Coral

/// Tolerant transcript decode (#18): one malformed message must not lose the history.
struct TranscriptDecodeTests {
    @Test func dropsOneBadMessageKeepsTheRest() throws {
        // Middle element is missing the required `role` → it's dropped, the others survive.
        let json = #"""
        [{"id":"11111111-1111-1111-1111-111111111111","role":"user","text":"hi"},
         {"id":"22222222-2222-2222-2222-222222222222","text":"no role"},
         {"id":"33333333-3333-3333-3333-333333333333","role":"assistant","text":"hey"}]
        """#
        let msgs = try #require(AppModel.decodeMessagesTolerantly(Data(json.utf8)))
        #expect(msgs.count == 2)
        #expect(msgs.first?.text == "hi")
        #expect(msgs.last?.text == "hey")
    }

    @Test func cleanTranscriptDecodesWhole() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","role":"user","text":"a"}]"#
        #expect(AppModel.decodeMessagesTolerantly(Data(json.utf8))?.count == 1)
    }

    @Test func totalGarbageReturnsNil() {
        #expect(AppModel.decodeMessagesTolerantly(Data("not json".utf8)) == nil)
    }
}

/// Pure parsing of `git status --porcelain -z` + `--numstat` (CodeGit #13): path edge
/// cases (spaces, non-ASCII, renames, binaries) must survive without a real repo.
struct CodeGitParseTests {
    @Test func parsesKindsCountsSpacesAndUnicode() {
        let numstat = "12\t3\tsrc/app.swift\n-\t-\tbin.dat\n5\t0\tdir/á é.txt\n"
        let statusZ = " M src/app.swift\u{0}?? new file.txt\u{0}D  gone.swift\u{0}A  added.swift\u{0} M dir/á é.txt\u{0}"
        let files = CodeGit.parseChangedFiles(numstat: numstat, statusZ: statusZ)
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byPath["src/app.swift"]?.insertions == 12)
        #expect(byPath["src/app.swift"]?.deletions == 3)
        #expect(byPath["src/app.swift"]?.kind == .modified)
        #expect(byPath["new file.txt"]?.kind == .untracked)       // space in name survived
        #expect(byPath["gone.swift"]?.kind == .deleted)
        #expect(byPath["added.swift"]?.kind == .added)
        #expect(byPath["dir/á é.txt"]?.insertions == 5)           // unicode + space survived
    }

    @Test func binaryFileCountsAsZero() {
        let files = CodeGit.parseChangedFiles(numstat: "-\t-\tbin.dat\n", statusZ: " M bin.dat\u{0}")
        #expect(files.first?.insertions == 0 && files.first?.deletions == 0)
    }

    @Test func renameConsumesTwoFieldsWithoutDuplicating() {
        let statusZ = "R  new.txt\u{0}old.txt\u{0} M other.swift\u{0}"
        let files = CodeGit.parseChangedFiles(numstat: "", statusZ: statusZ)
        #expect(files.count == 2)                                 // old path isn't a 3rd entry
        #expect(files.contains { $0.kind == .renamed })
        #expect(files.contains { $0.path == "other.swift" })
    }
}

/// Records every call and returns canned text based on the prompt kind. Thread-safe
/// because delegated workers now run concurrently.
private final class MockRunner: OneShotRunner, @unchecked Sendable {
    struct Call: Equatable { let provider: AIProvider; let model: String }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    var planJSON = "[]"

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        lock.lock(); _calls.append(Call(provider: provider, model: model)); lock.unlock()
        let text: String
        if prompt.contains("JSON array") { text = planJSON }
        else if prompt.contains("Combine your agents") { text = "FINAL ANSWER" }
        else { text = "result:\(model)" }
        return OneShotResult(text: text, tokens: 10, costUSD: 0.01, provider: provider, model: model)
    }
}

/// Thread-safe event collector: `MetaOrchestrator.run` invokes `onEvent` from
/// CONCURRENT worker tasks (the delegate phase runs a task group), so appends must be
/// locked — an unsynchronized `Array.append` from parallel tasks corrupts the buffer
/// and crashes (EXC_BAD_ACCESS). Mirrors `MockRunner`'s locking.
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [MetaEvent] = []
    func append(_ event: MetaEvent) { lock.lock(); _events.append(event); lock.unlock() }
    var events: [MetaEvent] { lock.lock(); defer { lock.unlock() }; return _events }
}

private func makeStrategy() -> Strategy {
    let orch = AgentRole(name: "orchestrator", role: .orchestrator, model: .opus48,
                         systemPrompt: "", description: "Lead", count: 1, isOrchestrator: true)
    let researcher = AgentRole(name: "researcher", role: .researcher, model: .sonnet5,
                               provider: .claude, systemPrompt: "", description: "Investigate", count: 1)
    var writer = AgentRole(name: "writer", role: .worker, model: .haiku45,
                           systemPrompt: "", description: "Write", count: 1)
    writer.provider = .gemini
    writer.providerModelID = "gemini-flash"
    return Strategy(name: "Test", description: "", roles: [orch, researcher, writer], orchestrationNotes: "")
}

struct MetaOrchestratorPureTests {
    @Test func readOnlyClaudeCommandForbidsEditTools() {
        // The loop verifier runs read-only: it must be able to read + run tests, but the
        // file-editing tools are forbidden so it can't modify the code it's judging.
        let normal = CLIOneShotRunner.command(for: .claude, prompt: "judge", model: "claude-haiku-4-5",
                                              permissionMode: "acceptEdits").args
        #expect(!normal.contains("--disallowedTools"))
        let ro = CLIOneShotRunner.command(for: .claude, prompt: "judge", model: "claude-haiku-4-5",
                                          permissionMode: "acceptEdits", readOnly: true).args
        guard let i = ro.firstIndex(of: "--disallowedTools") else {
            Issue.record("read-only claude command should disallow tools"); return
        }
        let forbidden = ro[i + 1]
        #expect(forbidden.contains("Edit") && forbidden.contains("Write")
                && forbidden.contains("MultiEdit") && forbidden.contains("NotebookEdit"))
    }

    @Test func resolvesModelIdPerProvider() {
        let claude = AgentRole(name: "a", role: .worker, model: .sonnet5, systemPrompt: "", description: "")
        #expect(MetaOrchestrator.modelID(for: claude) == "claude-sonnet-5")
        var gem = claude; gem.provider = .gemini; gem.providerModelID = "gemini-pro"
        #expect(MetaOrchestrator.modelID(for: gem) == "gemini-pro")
    }

    @Test func parsesPlanJSON() {
        let s = makeStrategy()
        let plan = MetaOrchestrator.parsePlan(
            #"Sure! [{"role":"researcher","task":"look into X"},{"role":"writer","task":"draft Y"}]"#,
            workers: s.subagentRoles, task: "T")
        #expect(plan == [.init(roleName: "researcher", task: "look into X"),
                         .init(roleName: "writer", task: "draft Y")])
    }

    @Test func planFallsBackWhenUnparseable() {
        let s = makeStrategy()
        let plan = MetaOrchestrator.parsePlan("no json here", workers: s.subagentRoles, task: "the task")
        // One subtask per worker, each carrying the whole task.
        #expect(plan.count == 2)
        #expect(plan.allSatisfy { $0.task == "the task" })
    }
}

struct MetaOrchestratorRunTests {
    @Test func runsPlanDelegateSynthesizeAcrossProviders() async {
        let strategy = makeStrategy()
        let runner = MockRunner()
        runner.planJSON = #"[{"role":"researcher","task":"research it"},{"role":"writer","task":"write it"}]"#
        let box = EventBox()

        let final = await MetaOrchestrator.run(strategy: strategy, task: "Do the thing", cwd: nil,
                                               runner: runner) { box.append($0) }

        // Final synthesized answer.
        #expect(final == "FINAL ANSWER")
        #expect(box.events.contains(.assistantText("FINAL ANSWER")))
        #expect(box.events.contains(.finished))

        // Four calls total; workers run concurrently so their order isn't fixed.
        let calls = runner.calls
        #expect(calls.count == 4)
        // Orchestrator (plan + synthesize) ran twice on Opus.
        #expect(calls.filter { $0 == .init(provider: .claude, model: "claude-opus-4-8") }.count == 2)
        // The researcher ran on Claude Sonnet, the writer on a DIFFERENT provider (Gemini).
        #expect(calls.contains(.init(provider: .claude, model: "claude-sonnet-5")))
        #expect(calls.contains(.init(provider: .gemini, model: "gemini-flash")))

        // Usage is emitted as a per-step DELTA (so the live counter climbs during the
        // run, not just at the end) — one event per call, summing to the total.
        let usageDeltas = box.events.compactMap { if case .usage(let t, let c, _) = $0 { return (t, c) } else { return nil } }
        #expect(usageDeltas.count == 4)
        #expect(usageDeltas.reduce(0) { $0 + $1.0 } == 40)
        #expect(abs(usageDeltas.reduce(0.0) { $0 + $1.1 } - 0.04) < 0.0001)
        // Phases were announced in order.
        let phases = box.events.compactMap { if case .phase(let p) = $0 { return p } else { return nil } }
        #expect(phases == ["plan", "delegate", "synthesize"])
    }

    @Test func soloTeamAnswersDirectly() async {
        let orch = AgentRole(name: "solo", role: .orchestrator, model: .opus48,
                             systemPrompt: "", description: "", count: 1, isOrchestrator: true)
        let strategy = Strategy(name: "Solo", description: "", roles: [orch], orchestrationNotes: "")
        let runner = MockRunner()
        let box = EventBox()
        let final = await MetaOrchestrator.run(strategy: strategy, task: "Just answer", cwd: nil,
                                               runner: runner) { box.append($0) }
        #expect(final == "result:claude-opus-4-8")
        #expect(runner.calls.count == 1)   // no plan/synthesize, just one answer
    }
}

struct ProviderUsageEstimateTests {

    @Test func estimatesTokensFromTextLength() {
        // ~4 chars/token across prompt + output.
        let n = estimateTokens(prompt: String(repeating: "a", count: 400),
                               output: String(repeating: "b", count: 400))
        #expect(n == 200)
        // Never zero, even for empty text.
        #expect(estimateTokens(prompt: "", output: "") == 1)
    }

    @Test func estimatedCostUsesRealPriceWhenKnown() {
        // A Claude model has a real price → blended (input+output)/2 per M.
        let cost = CLIOneShotRunner.estimatedCostUSD(tokens: 1_000_000, model: "claude-sonnet-5")
        #expect(cost == (3.0 + 15.0) / 2)   // blended per-M for 1M tokens
    }

    @Test func estimatedCostFallsBackForUnknownModel() {
        let cost = CLIOneShotRunner.estimatedCostUSD(tokens: 1_000_000, model: "some-codex-model")
        #expect(cost == Constants.CostModel.estimatedBlendedFallbackPerM)
    }
}
