//
//  ClaudeRunner.swift
//  StrategyForge
//
//  Runs Claude Code headless in a repo and streams its output for the in-app chat.
//  This honors the generated .claude/agents + CLAUDE.md and uses the user's own
//  Claude Code plan (no API key). It spawns `claude -p … --output-format stream-json`
//  as a subprocess, so it requires the app to run WITHOUT App Sandbox (direct
//  notarized distribution). The stream parser is pure and unit-tested.
//

import Foundation

/// A single event streamed back from a headless Claude Code run.
/// A task item from Claude Code's TodoWrite tool.
struct AgentTodo: Sendable, Equatable {
    let content: String
    let status: String   // "pending" | "in_progress" | "completed"
}

enum ChatEvent: Sendable, Equatable {
    case assistantText(String)          // a complete assistant text block
    case assistantDelta(String)         // a streamed text fragment (partial messages)
    case tool(name: String, detail: String?)  // a tool the agent invoked (+ target)
    case delegated(String)              // the orchestrator delegated to this subagent
    case todos([AgentTodo])             // the agent's task list (TodoWrite)
    case fileEdited(String)             // absolute path of a file the agent wrote/edited
    case denied([String])               // tool uses the run wasn't permitted to perform
    case usage(tokens: Int, costUSD: Double)  // consumption for this turn
    case finished                       // the run completed successfully
    case failed(String)                 // the run could not start / errored
}

/// Pure, tolerant parser for Claude Code's `--output-format stream-json` lines.
/// Kept separate from process handling so it can be tested without spawning.
enum ClaudeStreamParser {

    /// Parse one NDJSON line into zero or more chat events. Unknown/invalid lines
    /// yield nothing (forward-compatible with schema changes).
    static func events(from line: String) -> [ChatEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let type = obj["type"] as? String

        // Streamed text fragment (with --include-partial-messages).
        if type == "stream_event",
           let event = obj["event"] as? [String: Any],
           event["type"] as? String == "content_block_delta",
           let delta = event["delta"] as? [String: Any],
           delta["type"] as? String == "text_delta",
           let text = delta["text"] as? String, !text.isEmpty {
            return [.assistantDelta(text)]
        }

        // Assistant turn: pull text + tool_use blocks from message.content.
        if type == "assistant", let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            var events: [ChatEvent] = []
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        events.append(.assistantText(text))
                    }
                case "tool_use":
                    if let name = block["name"] as? String {
                        let input = block["input"] as? [String: Any]
                        // Delegation (the differentiator): surface WHICH subagent runs.
                        if name == "Task" || name == "Agent" {
                            let sub = (input?["subagent_type"] as? String)
                                ?? (input?["description"] as? String) ?? name
                            events.append(.delegated(sub))
                        } else if name == "TodoWrite", let todos = input?["todos"] as? [[String: Any]] {
                            events.append(.todos(todos.map {
                                AgentTodo(content: $0["content"] as? String ?? "",
                                          status: $0["status"] as? String ?? "pending")
                            }))
                        } else {
                            events.append(.tool(name: name, detail: toolDetail(name, input)))
                        }
                        // Note which files it edits, for a post-turn summary.
                        if ["Write", "Edit", "MultiEdit", "NotebookEdit"].contains(name),
                           let path = input?["file_path"] as? String {
                            events.append(.fileEdited(path))
                        }
                    }
                default:
                    break
                }
            }
            return events
        }

        // Final result line — carries token usage and success/failure.
        if type == "result" {
            var events: [ChatEvent] = []
            if let denials = obj["permission_denials"] as? [[String: Any]], !denials.isEmpty {
                let items = denials.map { den -> String in
                    let name = den["tool_name"] as? String ?? "tool"
                    let input = den["tool_input"] as? [String: Any]
                    let detail = (input?["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
                        ?? (input?["command"] as? String) ?? ""
                    return detail.isEmpty ? name : "\(name) \(detail)"
                }
                events.append(.denied(items))
            }
            if let usage = obj["usage"] as? [String: Any] {
                let input = (usage["input_tokens"] as? Int) ?? 0
                let output = (usage["output_tokens"] as? Int) ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let tokens = input + output + cacheCreate
                let cost = (obj["total_cost_usd"] as? Double) ?? 0
                if tokens > 0 || cost > 0 { events.append(.usage(tokens: tokens, costUSD: cost)) }
            }
            if let subtype = obj["subtype"] as? String, subtype != "success" {
                events.append(.failed((obj["result"] as? String) ?? subtype))
            } else {
                events.append(.finished)
            }
            return events
        }

        return []
    }

    /// A short human-readable "what it's acting on" for a tool use.
    private static func toolDetail(_ name: String, _ input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let path = input["file_path"] as? String { return (path as NSString).lastPathComponent }
        if let cmd = input["command"] as? String {
            return cmd.count > 60 ? String(cmd.prefix(60)) + "…" : cmd
        }
        if let pattern = input["pattern"] as? String { return pattern }
        if let url = input["url"] as? String { return url }
        if let q = input["query"] as? String { return q }
        return nil
    }
}

/// Spawns and streams a headless Claude Code run. Not sandbox-compatible.
enum ClaudeRunner {

    /// Stream a single turn. `continueSession` resumes the repo's latest Claude Code
    /// session so the chat is multi-turn. `model` is the orchestrator (session) model.
    nonisolated static func stream(
        binary: String,
        repoPath: String,
        prompt: String,
        model: String,
        sessionID: String,
        resume: Bool,
        permissionMode: String,
        extraDirs: [String] = []
    ) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            // Resolving the binary spawns an interactive login shell (to source the
            // user's PATH), which blocks for a beat. The AsyncStream closure runs
            // synchronously on the caller — the main actor — so do ALL of the setup
            // and launch on a background queue to keep the UI responsive.
            DispatchQueue.global(qos: .userInitiated).async {
            // A GUI app doesn't inherit the user's shell PATH, so resolve `claude`
            // to an absolute path (via an interactive login shell + known locations)
            // and run it DIRECTLY — no shell, so no PATH/quoting surprises.
            guard let resolved = resolveBinary(binary) else {
                continuation.yield(.failed("Couldn't find the `claude` binary. Set its full path in Settings (run `which claude` in Terminal)."))
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolved)
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            var args = ["--model", model, "--output-format", "stream-json", "--verbose",
                        "--include-partial-messages", "--permission-mode", permissionMode]
            // A per-chat session id keeps chats on the same repo from mixing.
            if resume {
                args.append(contentsOf: ["--resume", sessionID])
            } else {
                args.append(contentsOf: ["--session-id", sessionID])
            }
            // Grant read access to the folders of any attached files.
            for dir in extraDirs { args.append(contentsOf: ["--add-dir", dir]) }
            args.append(contentsOf: ["-p", prompt])
            process.arguments = args

            // Give claude (and the git/node subprocesses it spawns) a sane PATH.
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let binDir = (resolved as NSString).deletingLastPathComponent
            env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let buffer = LineBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in buffer.append(data) {
                    for event in ClaudeStreamParser.events(from: line) {
                        continuation.yield(event)
                    }
                }
            }

            process.terminationHandler = { proc in
                stdout.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.yield(.failed(trimmed.isEmpty ? "claude exited with code \(proc.terminationStatus)" : trimmed))
                } else {
                    continuation.yield(.finished)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                // Most commonly: App Sandbox is on, or `claude` isn't found.
                continuation.yield(.failed(error.localizedDescription))
                continuation.finish()
            }
            } // DispatchQueue.global
        }
    }

    /// Resolve the `claude` binary to an absolute executable path.
    nonisolated static func resolveBinary(_ configured: String) -> String? {
        let fm = FileManager.default
        let name = configured.isEmpty ? "claude" : configured

        // 1. An absolute path the user configured.
        if name.hasPrefix("/"), fm.isExecutableFile(atPath: name) { return name }

        // 2. Ask an interactive login shell (sources ~/.zshrc → nvm/npm/Homebrew).
        if let viaShell = which(name), fm.isExecutableFile(atPath: viaShell) { return viaShell }

        // 3. Fall back to common install locations.
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude", "\(home)/bin/claude",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// `command -v <name>` via an interactive login shell; nil if not found.
    private nonisolated static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "command -v \(name)"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return (path?.isEmpty == false) ? path : nil
    }
}

/// Accumulates streamed bytes and emits complete lines. Thread-safe: the process
/// readability handler is called on a background queue.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data[data.startIndex..<nl]
            if let line = String(data: lineData, encoding: .utf8) { lines.append(line) }
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }
}
