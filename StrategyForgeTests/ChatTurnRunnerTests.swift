//
//  ChatTurnRunnerTests.swift
//  StrategyForgeTests
//
//  Drives ChatViewModel.runTurn through a FAKE ChatTurnRunner (the #12 seam), so the
//  event-handling logic — text accumulation, edited files, usage totals, failures — is
//  tested without spawning a `claude` process.
//

import Testing
import Foundation
@testable import Coral

/// A ChatTurnRunner that replays a scripted list of events as a finished stream.
private struct FakeTurnRunner: ChatTurnRunner {
    let events: [ChatEvent]

    private func replay() -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            for e in events { continuation.yield(e) }
            continuation.finish()
        }
    }
    func stream(binary: String, repoPath: String, prompt: String, model: String,
                sessionID: String, resume: Bool, permissionMode: String,
                extraDirs: [String]) -> AsyncStream<ChatEvent> { replay() }
    func streamAsking(binary: String, repoPath: String, prompt: String, model: String,
                      sessionID: String, resume: Bool, extraDirs: [String],
                      responder: PermissionResponder) -> AsyncStream<ChatEvent> { replay() }
}

@MainActor
struct ChatTurnRunnerTests {

    private func makeVM(_ events: [ChatEvent]) -> ChatViewModel {
        let config = Configuration(name: "T", strategy: StrategyLibrary.solo())
        let vm = ChatViewModel(config: config, binary: "claude", turnRunner: FakeTurnRunner(events: events))
        vm.messages = [ChatMessage(role: .assistant, text: "")]
        return vm
    }

    @Test func accumulatesDeltasEditedFilesAndUsage() async {
        let vm = makeVM([
            .assistantDelta("Hello "),
            .assistantDelta("world"),
            .fileEdited("/repo/A.swift"),
            .fileEdited("/repo/A.swift"),   // duplicate must not double-list
            .fileEdited("/repo/B.swift"),
            .usage(tokens: 120, costUSD: 0.03),
            .usage(tokens: 30, costUSD: 0.01),
            .finished,
        ])
        _ = await vm.runTurn(text: "hi", repo: "/repo", sessionID: "s", resume: false,
                             assistantIndex: 0, binary: "claude", model: "m",
                             permissionMode: "acceptEdits")
        #expect(vm.messages[0].text == "Hello world")
        #expect(vm.editedFiles == ["/repo/A.swift", "/repo/B.swift"])
        #expect(vm.totalTokens == 150)
        #expect(abs(vm.totalCostUSD - 0.04) < 0.0001)
        #expect(vm.errorText == nil)
    }

    @Test func surfacesFailure() async {
        let vm = makeVM([.failed("boom")])
        _ = await vm.runTurn(text: "hi", repo: "/repo", sessionID: "s", resume: false,
                             assistantIndex: 0, binary: "claude", model: "m",
                             permissionMode: "acceptEdits")
        #expect(vm.errorText == "boom")
    }

    @Test func missingSessionOnResumeSignalsRetryWithoutError() async {
        // A "No conversation found" failure on a resume must NOT surface as an error — it
        // signals a fresh retry (runTurn returns true).
        let vm = makeVM([.failed("No conversation found for session")])
        let sessionMissing = await vm.runTurn(text: "hi", repo: "/repo", sessionID: "s",
                                              resume: true, assistantIndex: 0, binary: "claude",
                                              model: "m", permissionMode: "acceptEdits")
        #expect(sessionMissing)
        #expect(vm.errorText == nil)
    }

    /// A OneShotRunner that echoes a fixed answer — for the second-opinion path.
    private struct StubOneShot: OneShotRunner {
        let answer: String
        func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
            OneShotResult(text: answer, tokens: 0, costUSD: 0, provider: provider, model: model)
        }
    }

    @Test func secondOpinionAppendsALabeledAnswerOffTheMainRunPath() async {
        let config = Configuration(name: "T", strategy: StrategyLibrary.solo())
        let vm = ChatViewModel(config: config, binary: "claude")
        vm.messages = [ChatMessage(role: .user, text: "Is this correct?"),
                       ChatMessage(role: .assistant, text: "Claude says yes.")]

        await vm.secondOpinion(provider: .openai, model: "gpt-x", cwd: nil,
                               runner: StubOneShot(answer: "Codex disagrees."),
                               headerPrefix: "**Second opinion — Codex**\n\n")

        #expect(vm.messages.count == 3)
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.text == "**Second opinion — Codex**\n\nCodex disagrees.")
        #expect(!vm.isRunning)                 // never touched the main run flag
        #expect(!vm.isSecondOpinionRunning)    // cleared after
    }
}
