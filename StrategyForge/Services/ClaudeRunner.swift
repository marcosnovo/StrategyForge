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
    case commandStarted(id: String, command: String)  // a Bash command began (id links to output)
    case commandOutput(id: String, output: String)     // a tool_result's output text
    case delegated(String)              // the orchestrator delegated to this subagent
    case todos([AgentTodo])             // the agent's task list (TodoWrite)
    case fileEdited(String)             // absolute path of a file the agent wrote/edited
    case skillUsed(String)              // an Agent Skill the model pulled into context
    case denied([String])               // tool uses the run wasn't permitted to perform
    case usage(tokens: Int, costUSD: Double)  // authoritative run total (result line)
    case modelUsage(model: String, tokens: Int)  // per-message usage tagged with its model (#8)
    case permissionRequest(id: String, toolName: String, detail: String)  // live approval gate
    case finished                       // the run completed successfully
    case failed(String)                 // the run could not start / errored
}

/// Lets the UI answer a live `can_use_tool` permission request by writing a
/// `control_response` back to the running `claude` process's stdin. Thread-safe;
/// created per interactive run and attached once the process is launched.
final class PermissionResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdin: FileHandle?
    private var pendingInput: [String: [String: Any]] = [:]

    func attach(_ handle: FileHandle) { lock.lock(); stdin = handle; lock.unlock() }
    func remember(id: String, input: [String: Any]) { lock.lock(); pendingInput[id] = input; lock.unlock() }

    /// Approve or deny the tool use `id`. Approving echoes the original input back
    /// (the `can_use_tool` contract), denying returns a short reason.
    func respond(id: String, allow: Bool) {
        lock.lock()
        let input = pendingInput.removeValue(forKey: id) ?? [:]
        let handle = stdin
        lock.unlock()
        let inner: [String: Any] = allow
            ? ["behavior": "allow", "updatedInput": input]
            : ["behavior": "deny", "message": "Denied by the user."]
        let msg: [String: Any] = ["type": "control_response",
                                  "response": ["subtype": "success",
                                               "request_id": id, "response": inner]]
        guard var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0x0A)
        try? handle?.write(contentsOf: data)
    }
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
                        } else if name == "Skill" {
                            // Claude Code surfaces a skill as a Skill tool_use; the slug
                            // is in `command`/`name`/`skill` depending on version.
                            let slug = (input?["command"] as? String)
                                ?? (input?["name"] as? String)
                                ?? (input?["skill"] as? String) ?? "skill"
                            events.append(.skillUsed(slug))
                        } else {
                            events.append(.tool(name: name, detail: toolDetail(name, input)))
                        }
                        // Bash: remember the command so its later output (tool_result)
                        // can be shown in the code-mode terminal.
                        if name == "Bash", let id = block["id"] as? String,
                           let cmd = input?["command"] as? String {
                            events.append(.commandStarted(id: id, command: cmd))
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
            // Per-message token usage tagged with the model that produced it — the
            // native, exact source for the #8 per-model breakdown (subagent messages
            // carry their own model, e.g. Haiku).
            if let modelID = message["model"] as? String,
               let u = message["usage"] as? [String: Any] {
                let t = (u["input_tokens"] as? Int ?? 0) + (u["output_tokens"] as? Int ?? 0)
                    + (u["cache_creation_input_tokens"] as? Int ?? 0)
                    + (u["cache_read_input_tokens"] as? Int ?? 0)
                if t > 0 { events.append(.modelUsage(model: modelID, tokens: t)) }
            }
            return events
        }

        // User turn carrying tool_result blocks — the output of the tools/commands.
        if type == "user", let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            var events: [ChatEvent] = []
            for block in content where block["type"] as? String == "tool_result" {
                guard let id = block["tool_use_id"] as? String else { continue }
                let text = toolResultText(block["content"])
                events.append(.commandOutput(id: id, output: text))
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
                let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
                let tokens = input + output + cacheCreate + cacheRead
                let cost = (obj["total_cost_usd"] as? Double) ?? 0
                if tokens > 0 || cost > 0 { events.append(.usage(tokens: tokens, costUSD: cost)) }
            }
            // A run can carry `is_error: true` while still reporting subtype "success"
            // (notably a 401 auth failure), so check both — otherwise it reads as a
            // silent empty finish.
            let subtype = obj["subtype"] as? String
            let isError = (obj["is_error"] as? Bool) == true
            if isError || (subtype != nil && subtype != "success") {
                let raw = (obj["result"] as? String) ?? subtype ?? "The run failed."
                if (obj["api_error_status"] as? Int) == 401 || raw.lowercased().contains("authenticate") {
                    events.append(.failed("Claude couldn't authenticate (401). Your saved Claude login looks expired — open Terminal, run `claude`, sign in to your plan, then retry."))
                } else {
                    events.append(.failed(raw))
                }
            } else {
                events.append(.finished)
            }
            return events
        }

        return []
    }

    /// Flatten a tool_result's `content` (a String, or an array of text blocks).
    private static func toolResultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
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
        extraDirs: [String] = [],
        effort: String? = nil
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
            // Reasoning effort, when the caller pins it (loops do; chat leaves it nil
            // and steers effort via a prompt directive instead).
            if let effort { args.append(contentsOf: ["--effort", effort]) }
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
            sanitizeClaudeAuth(&env)
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // Inactivity watchdog: an unattended loop can wedge on a hung turn and sit
            // forever holding the user's plan. Terminate after a long silence — reset by
            // any output, so a legit long tool run (a multi-minute test) is safe.
            let watchdog = InactivityWatchdog(timeout: 600) { [weak process] in
                if process?.isRunning == true { process?.terminate() }
            }

            let buffer = LineBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                watchdog.bump()
                for line in buffer.append(data) {
                    for event in ClaudeStreamParser.events(from: line) {
                        continuation.yield(event)
                    }
                }
            }

            // Drain stderr continuously: a pipe holds ~64KB, and claude (plus the
            // MCP servers/hooks it spawns, which inherit this fd) can exceed that
            // mid-turn. Left unread, the child blocks in write(2) and never exits.
            let errBuffer = ByteBuffer()
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                watchdog.bump()
                errBuffer.append(data)
            }

            process.terminationHandler = { proc in
                LiveProcesses.deregister(proc)
                watchdog.cancel()
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                // The readability handlers race with termination and can miss the
                // last chunks still sitting in the pipes — including the closing
                // `result` line (usage/denials/errors). Drain them without blocking
                // (grandchild processes may still hold the write ends open).
                var lines = buffer.append(drainPipe(stdout.fileHandleForReading))
                lines += buffer.drain()
                for line in lines {
                    for event in ClaudeStreamParser.events(from: line) { continuation.yield(event) }
                }
                if watchdog.didFire {
                    // The watchdog killed a wedged turn — say so plainly rather than
                    // reporting it as a generic SIGTERM exit.
                    continuation.yield(.failed("The turn stalled with no output for 10 minutes and was stopped."))
                } else if proc.terminationStatus != 0 {
                    errBuffer.append(drainPipe(stderr.fileHandleForReading))
                    let errText = String(data: errBuffer.contents(), encoding: .utf8) ?? ""
                    let trimmed = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.yield(.failed(trimmed.isEmpty ? "claude exited with code \(proc.terminationStatus)" : trimmed))
                } else {
                    continuation.yield(.finished)
                }
                continuation.finish()
            }

            // The consumer can cancel while setup is still running (resolveBinary can
            // take hundreds of ms), firing onTermination BEFORE process.run(). The gate
            // makes launch-vs-cancel mutually exclusive so a cancelled turn never
            // spawns an orphan `claude` nobody can stop (see ProviderRun's ProcessBox).
            let gate = LaunchGate()
            continuation.onTermination = { _ in
                // Break the read handlers' hold on the continuation, then stop claude.
                watchdog.cancel()
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                gate.cancel()
            }

            do {
                guard try gate.launch(process) else {
                    // Cancelled before launch — the consumer is gone; don't spawn.
                    continuation.finish()
                    return
                }
                LiveProcesses.register(process)   // terminated on app quit, not orphaned
                watchdog.start()                  // begin the idle clock only once it's live
            } catch {
                // Most commonly: App Sandbox is on, or `claude` isn't found.
                continuation.yield(.failed(error.localizedDescription))
                continuation.finish()
            }
            } // DispatchQueue.global
        }
    }

    /// Like `stream`, but drives the run via `--input-format stream-json` so the CLI
    /// can ASK for tool permission mid-turn (`control_request`/`can_use_tool`). The
    /// prompt is written to stdin (kept open), and `responder` writes the user's
    /// allow/deny back. Used only when the chat's mode is "Ask" — the default `-p`
    /// path above is untouched. NOTE: the exact control wire-format is validated
    /// against a live run; parsing here is tolerant of field-name variants.
    nonisolated static func streamAsking(
        binary: String, repoPath: String, prompt: String, model: String,
        sessionID: String, resume: Bool, extraDirs: [String],
        responder: PermissionResponder
    ) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let resolved = resolveBinary(binary) else {
                    continuation.yield(.failed("Couldn't find the `claude` binary.")); continuation.finish(); return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: resolved)
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
                var args = ["--print", "--input-format", "stream-json",
                            "--output-format", "stream-json", "--verbose",
                            "--include-partial-messages", "--model", model,
                            "--permission-mode", "default"]
                if resume { args += ["--resume", sessionID] } else { args += ["--session-id", sessionID] }
                for dir in extraDirs { args += ["--add-dir", dir] }
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let binDir = (resolved as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                sanitizeClaudeAuth(&env)
                process.environment = env

                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = stderr
                responder.attach(stdin.fileHandleForWriting)

                let buffer = LineBuffer()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                    for line in buffer.append(data) {
                        // Intercept a live permission request before the generic parser.
                        if let req = permissionRequest(from: line) {
                            responder.remember(id: req.id, input: req.input)
                            continuation.yield(.permissionRequest(id: req.id, toolName: req.tool, detail: req.detail))
                            continue
                        }
                        for event in ClaudeStreamParser.events(from: line) {
                            continuation.yield(event)
                            // Print-mode with stream-json input keeps stdin open; once the
                            // turn's result lands — success OR error — close it so the CLI
                            // exits cleanly (an error result would otherwise leave the CLI
                            // waiting for the next message and the turn spinning forever).
                            if case .finished = event { try? stdin.fileHandleForWriting.close() }
                            if case .failed = event { try? stdin.fileHandleForWriting.close() }
                        }
                    }
                }
                let errBuffer = ByteBuffer()
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                    errBuffer.append(data)
                }
                process.terminationHandler = { proc in
                    LiveProcesses.deregister(proc)
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    var lines = buffer.append(drainPipe(stdout.fileHandleForReading))
                    lines += buffer.drain()
                    for line in lines {
                        for event in ClaudeStreamParser.events(from: line) { continuation.yield(event) }
                    }
                    if proc.terminationStatus != 0 {
                        errBuffer.append(drainPipe(stderr.fileHandleForReading))
                        let t = (String(data: errBuffer.contents(), encoding: .utf8) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.yield(.failed(t.isEmpty ? "claude exited with code \(proc.terminationStatus)" : t))
                    } else {
                        continuation.yield(.finished)
                    }
                    continuation.finish()
                }
                // Same launch-vs-cancel gate as `stream`: a cancellation during setup
                // must not fall through to process.run() and orphan the CLI (worse
                // here — with no watchdog, a blocked permission ask never exits).
                let gate = LaunchGate()
                continuation.onTermination = { _ in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    gate.cancel()
                }
                do {
                    guard try gate.launch(process) else {
                        // Cancelled before launch — the consumer is gone; don't spawn.
                        continuation.finish()
                        return
                    }
                    LiveProcesses.register(process)
                    // Send the user's turn as one stream-json message, then leave stdin
                    // open so control_responses can be written during the turn.
                    let userMsg: [String: Any] = ["type": "user",
                        "message": ["role": "user", "content": [["type": "text", "text": prompt]]]]
                    if var data = try? JSONSerialization.data(withJSONObject: userMsg) {
                        data.append(0x0A)
                        try? stdin.fileHandleForWriting.write(contentsOf: data)
                    }
                } catch {
                    continuation.yield(.failed(error.localizedDescription)); continuation.finish()
                }
            }
        }
    }

    /// Parse a `control_request` / `can_use_tool` line (tolerant of field variants),
    /// or nil if the line isn't one.
    private static func permissionRequest(from line: String) -> (id: String, tool: String, input: [String: Any], detail: String)? {
        guard let data = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["type"] as? String) == "control_request" else { return nil }
        let req = (obj["request"] as? [String: Any]) ?? obj
        guard (req["subtype"] as? String) == "can_use_tool" else { return nil }
        let id = (obj["request_id"] as? String) ?? (req["request_id"] as? String) ?? UUID().uuidString
        let tool = (req["tool_name"] as? String) ?? (req["tool"] as? String) ?? "tool"
        let input = (req["input"] as? [String: Any]) ?? [:]
        // Pretty-print the tool input so the modal shows exactly what's being asked.
        var detail = ""
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            detail = s
        }
        return (id, tool, input, detail)
    }

    /// Coral runs on the user's own Claude *subscription* (the OAuth login that
    /// `claude` stores after an interactive sign-in). But `claude` prefers an
    /// `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` from its environment over that
    /// stored login. A GUI app launched from a shell (or Xcode) that exports such a
    /// key inherits it and fails with `401 Invalid authentication credentials` even
    /// though the plan is connected. Strip them so the stored login is always used.
    ///
    /// It ALSO pins `CLAUDE_CONFIG_DIR` deterministically (see `resolveClaudeConfigDir`):
    /// otherwise the run 401s intermittently depending on how the app was launched —
    /// from a shell/Xcode that exports a good `CLAUDE_CONFIG_DIR` it works; from Finder
    /// it silently falls back to a stale `~/.claude`. Pinning a dir that actually holds
    /// a login makes runs reproducible and matches the login the user's own CLI uses.
    nonisolated static func sanitizeClaudeAuth(_ env: inout [String: String]) {
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] { env[key] = nil }
        if let dir = resolveClaudeConfigDir() { env["CLAUDE_CONFIG_DIR"] = dir }
    }

    /// The Claude config dir Coral should use, chosen deterministically: an inherited
    /// `CLAUDE_CONFIG_DIR` that actually holds a login wins; then well-known locations
    /// that contain a login file; else the default `~/.claude`. This is what fixes the
    /// "works from Xcode, 401s from Finder" flakiness — the run always targets a dir
    /// with a real login when one exists on disk.
    nonisolated static func resolveClaudeConfigDir() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        func hasLogin(_ dir: String) -> Bool {
            fm.fileExists(atPath: dir + "/.credentials.json")
                || fm.fileExists(atPath: dir + "/.claude.json")
        }
        var candidates: [String] = []
        if let inherited = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !inherited.isEmpty { candidates.append(inherited) }
        candidates.append("\(home)/.claude")
        // Dev convenience: the Xcode coding-assistant keeps its own working login here.
        candidates.append("\(home)/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig")
        return candidates.first(where: hasLogin) ?? candidates.first
    }

    // Resolved-path cache. `resolveBinary` spawns an interactive login shell (`which`,
    // ~hundreds of ms) and is called on every provider detect + run; caching avoids
    // re-paying that on every keystroke/refresh. Short TTL so a freshly-installed CLI is
    // still picked up soon, and each hit is re-validated with a cheap isExecutableFile.
    private static let binCacheLock = NSLock()
    nonisolated(unsafe) private static var binCache: [String: (path: String, at: Date)] = [:]

    /// Resolve the `claude` binary to an absolute executable path (cached).
    nonisolated static func resolveBinary(_ configured: String) -> String? {
        let fm = FileManager.default
        let name = configured.isEmpty ? "claude" : configured

        binCacheLock.lock()
        let cached = binCache[name]
        binCacheLock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 60, fm.isExecutableFile(atPath: cached.path) {
            return cached.path
        }
        let resolved = resolveBinaryUncached(name, fm: fm)
        if let resolved {
            binCacheLock.lock(); binCache[name] = (resolved, Date()); binCacheLock.unlock()
        }
        return resolved
    }

    private nonisolated static func resolveBinaryUncached(_ name: String, fm: FileManager) -> String? {
        // 1. An absolute path the user configured.
        if name.hasPrefix("/"), fm.isExecutableFile(atPath: name) { return name }

        // 2. Ask an interactive login shell (sources ~/.zshrc → nvm/npm/Homebrew).
        if let viaShell = which(name), fm.isExecutableFile(atPath: viaShell) { return viaShell }

        // 3. Fall back to common install locations by the binary's LEAF name, so a
        // fresh `npm install -g --prefix ~/.npm-global` is found even when that bin
        // dir isn't on the login-shell PATH. claude gets a couple of extra spots.
        let home = fm.homeDirectoryForCurrentUser.path
        let leaf = (name as NSString).lastPathComponent
        var candidates = [
            "\(home)/.npm-global/bin/\(leaf)",
            "/opt/homebrew/bin/\(leaf)", "/usr/local/bin/\(leaf)",
            "\(home)/.local/bin/\(leaf)", "\(home)/bin/\(leaf)",
        ]
        if leaf == "claude" { candidates.append("\(home)/.claude/local/claude") }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Read whatever is currently buffered in a pipe without blocking. Used at
    /// termination, where `readDataToEndOfFile` could hang forever if a grandchild
    /// process (an MCP server claude spawned) still holds the write end open.
    /// Internal so LoopRunner's mechanical gate can reuse it for the same hazard.
    nonisolated static func drainPipe(_ handle: FileHandle) -> Data {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        if flags != -1 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            result.append(contentsOf: chunk[0..<n])
        }
        return result
    }

    /// `command -v <name>` via an interactive login shell; nil if not found.
    private nonisolated static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Pass the name via the environment, NOT string-interpolated into the
        // command, so a name with shell metacharacters can't inject anything.
        process.arguments = ["-ilc", "command -v \"$SF_CLAUDE_BIN\""]
        var env = ProcessInfo.processInfo.environment
        env["SF_CLAUDE_BIN"] = name
        process.environment = env
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

/// Makes launching the `claude` subprocess and cancelling the stream mutually
/// exclusive. The stream's setup runs on a background queue, so a consumer
/// cancellation (stop, new turn, chat teardown) can fire `onTermination` before
/// `Process.run()` — the old `if process.isRunning { terminate() }` was a no-op
/// then, and the launch fell through anyway, spawning an orphan run feeding a dead
/// continuation. Mirrors ProviderRun's ProcessBox. Internal (not private) so the
/// launch/cancel ordering is unit-testable without spawning `claude` itself.
final class LaunchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    /// Launch `p` under the lock. Returns false WITHOUT launching when the stream
    /// was already cancelled; rethrows whatever `Process.run()` throws.
    func launch(_ p: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        try p.run()
        process = p
        return true
    }

    /// Mark the stream cancelled; stops the process if it was already launched,
    /// and makes any not-yet-run `launch` refuse to spawn.
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let p = process, p.isRunning { p.terminate() }
    }
}

/// Thread-safe raw byte accumulator (for stderr, which has no line semantics).
/// Internal so LoopRunner's mechanical gate can reuse it for the same job.
final class ByteBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
    }

    func contents() -> Data {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

/// Fires `onTimeout` when no output has arrived for `timeout` seconds — an INACTIVITY
/// watchdog, not a total cap: every `bump()` (from a stdout/stderr read) resets the
/// clock, so a legitimately long turn (a multi-minute test/build with a quiet CLI
/// stream) is never killed; only genuine silence — a hung, wedged turn — trips it.
/// The window is deliberately generous (10 min) for exactly that reason.
/// All `timer` access goes through `lock`: cancel() is called from BOTH the process
/// terminationHandler (arbitrary Foundation thread) and continuation.onTermination
/// (the consumer's cancelling thread), which race on a user stop landing alongside
/// a natural exit. Internal (not private) so the start/cancel ordering is testable.
final class InactivityWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.marcosnovo.coral.runner.watchdog")
    private let timeout: TimeInterval
    private let onTimeout: () -> Void
    private let lock = NSLock()
    private var lastActivity = DispatchTime.now()
    private var timer: DispatchSourceTimer?
    private var cancelled = false
    private var fired = false

    init(timeout: TimeInterval, onTimeout: @escaping () -> Void) {
        self.timeout = timeout
        self.onTimeout = onTimeout
    }

    func start() {
        lock.lock()
        // cancel() can land first (a child that exits before start(), or a consumer
        // cancellation racing the launch) — don't arm a timer nobody will stop.
        if cancelled { lock.unlock(); return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Poll at half the window so the worst-case detection lag is timeout×1.5.
        t.schedule(deadline: .now() + timeout, repeating: timeout / 2)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            // A cancel() that landed while this tick was already dequeued must
            // still win: never fire for a watchdog its owner has stopped.
            if self.cancelled { self.lock.unlock(); return }
            let idleNs = DispatchTime.now().uptimeNanoseconds &- self.lastActivity.uptimeNanoseconds
            let already = self.fired
            if !already && Double(idleNs) / 1_000_000_000 >= self.timeout { self.fired = true }
            let shouldFire = !already && self.fired
            self.lock.unlock()
            if shouldFire { self.onTimeout() }
        }
        timer = t
        lock.unlock()
        // Resuming outside the lock is safe: a racing cancel() already took the
        // source out of `timer` and called .cancel() on it, and resuming a
        // cancelled source just lets it deallocate without ever firing.
        t.resume()
    }

    func bump() {
        lock.lock(); lastActivity = .now(); lock.unlock()
    }

    /// Whether the watchdog (not the user/CLI) is what stopped the run.
    var didFire: Bool { lock.lock(); defer { lock.unlock() }; return fired }

    /// Idempotent; safe to call from multiple threads concurrently and before start().
    func cancel() {
        lock.lock()
        cancelled = true
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
    }
}

/// Accumulates streamed bytes and emits complete lines. Thread-safe: the process
/// readability handler is called on a background queue. Shared with ProviderInstaller's
/// streamed-output handling (it previously carried its own O(n²) copy).
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        // Walk newlines with a moving cursor and remove the consumed prefix ONCE at the
        // end — front-removing per line is O(n²) over a long turn's thousands of lines.
        var cursor = data.startIndex
        var lastNL: Data.Index?
        while let nl = data[cursor...].firstIndex(of: 0x0A) {
            if let line = String(data: data[cursor..<nl], encoding: .utf8) { lines.append(line) }
            lastNL = nl
            cursor = data.index(after: nl)
        }
        if let lastNL { data.removeSubrange(data.startIndex...lastNL) }
        return lines
    }

    /// Return any remaining buffered bytes as a final line (for output that didn't
    /// end with a newline) and clear the buffer.
    func drain() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else {
            data.removeAll(); return []
        }
        data.removeAll()
        return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [line]
    }
}
