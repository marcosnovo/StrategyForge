//
//  ChatTurnRunner.swift
//  StrategyForge
//
//  The seam (#12) between ChatViewModel and the CLI: it produces the per-turn
//  AsyncStream<ChatEvent> that ChatViewModel consumes. The real implementation just
//  forwards to ClaudeRunner (identical behavior); a fake can emit scripted events so the
//  event-handling logic (usage accumulation, edited-files, failures, …) is unit-testable
//  without spawning a `claude` process.
//

import Foundation

protocol ChatTurnRunner: Sendable {
    /// The proven `-p` path (every mode except "Ask").
    func stream(binary: String, repoPath: String, prompt: String, model: String,
                sessionID: String, resume: Bool, permissionMode: String,
                extraDirs: [String]) -> AsyncStream<ChatEvent>

    /// The `--input-format stream-json` path used by "Ask" mode (live per-tool permission).
    func streamAsking(binary: String, repoPath: String, prompt: String, model: String,
                      sessionID: String, resume: Bool, extraDirs: [String],
                      responder: PermissionResponder) -> AsyncStream<ChatEvent>
}

/// The real runner: spawns the `claude` CLI via ClaudeRunner. A thin pass-through so the
/// live behavior is exactly what it was before the seam was introduced.
struct CLIChatTurnRunner: ChatTurnRunner {
    func stream(binary: String, repoPath: String, prompt: String, model: String,
                sessionID: String, resume: Bool, permissionMode: String,
                extraDirs: [String]) -> AsyncStream<ChatEvent> {
        ClaudeRunner.stream(binary: binary, repoPath: repoPath, prompt: prompt, model: model,
                            sessionID: sessionID, resume: resume,
                            permissionMode: permissionMode, extraDirs: extraDirs)
    }

    func streamAsking(binary: String, repoPath: String, prompt: String, model: String,
                      sessionID: String, resume: Bool, extraDirs: [String],
                      responder: PermissionResponder) -> AsyncStream<ChatEvent> {
        ClaudeRunner.streamAsking(binary: binary, repoPath: repoPath, prompt: prompt, model: model,
                                  sessionID: sessionID, resume: resume,
                                  extraDirs: extraDirs, responder: responder)
    }
}
