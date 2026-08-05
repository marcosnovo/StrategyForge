//
//  ProviderRun.swift
//  StrategyForge
//
//  Level 2 primitive: a provider-agnostic *one-shot* agentic completion. Send a
//  prompt to a specific model on a specific provider's CLI (subscription login, no
//  API key) and get back its text + usage. The MetaOrchestrator drives many of
//  these to run a mixed-provider team (a GPT orchestrator delegating to Gemini
//  workers and a Claude advisor, etc.) — orchestration StrategyForge performs
//  itself, since no single vendor CLI can delegate across other vendors' models.
//
//  Only providers whose CLI is installed can run; others throw `.notInstalled`.
//  The Claude path is implemented and testable today; Codex/Gemini are wired as
//  adapters and verified once their CLIs are present.
//

import Foundation
import Darwin   // openpty / winsize — run Codex/Gemini under a PTY so they stream (and don't block-buffer)

/// A process-wide registry of live child CLI processes, so the app can terminate them
/// on quit instead of orphaning them (a running loop/chat subprocess otherwise survives
/// the app and keeps burning the user's plan). Thread-safe; register on spawn, deregister
/// on exit, `terminateAll()` from applicationWillTerminate.
enum LiveProcesses {
    private static let lock = NSLock()
    private static var procs: [ObjectIdentifier: Process] = [:]

    static func register(_ p: Process) { lock.lock(); procs[ObjectIdentifier(p)] = p; lock.unlock() }
    static func deregister(_ p: Process) { lock.lock(); procs[ObjectIdentifier(p)] = nil; lock.unlock() }

    static func terminateAll() {
        lock.lock(); let all = Array(procs.values); procs.removeAll(); lock.unlock()
        for p in all where p.isRunning { p.terminate() }
    }
}

/// The result of a single model call.
struct OneShotResult: Sendable, Equatable {
    var text: String
    var tokens: Int
    var costUSD: Double
    var provider: AIProvider
    var model: String
    /// True when `tokens`/`costUSD` are an ESTIMATE (the CLI reported no usage — Codex's
    /// plain output, Gemini), so the UI can mark them "~" instead of implying a real count.
    var estimated: Bool = false
}

/// Rough token estimate for a CLI that reports no usage: ~4 characters per token across
/// the prompt + the model's output. Coarse but honest — enough to stop cross-provider
/// runs reading as "0 tokens / $0", and always surfaced with a "~".
func estimateTokens(prompt: String, output: String) -> Int {
    max(1, (prompt.count + output.count) / 4)
}

enum OneShotError: Error, LocalizedError, Equatable {
    case notInstalled(AIProvider)
    case failed(String)
    /// The watchdog terminated the call after N seconds — reported distinctly so the
    /// user sees a timeout (and its cause) rather than an opaque "exited with code 143".
    case timedOut(Int)
    /// The CLI wants an interactive login (its saved session is stale/missing) — caught the
    /// moment it prints an auth prompt, so the run fails fast with a Reconnect affordance
    /// instead of hanging on a prompt no one can answer.
    case authRequired(AIProvider)
    /// The CLI produced NO output at all within the stall window — almost always a stuck
    /// login/handshake (esp. Gemini) that won't ever answer. Killed early so the user gets a
    /// fast, actionable failure instead of waiting out the full call watchdog.
    case stalled(AIProvider)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let p): return "\(p.displayName)'s CLI isn't installed. Connect it in Connect first."
        case .failed(let m): return m
        case .timedOut(let s):
            return "The model didn't finish within \(s / 60) minutes — the task or the combined agent output may be too large. Try splitting the task, using fewer agents, or a faster model."
        case .authRequired(let p):
            return "\(p.displayName) needs you to sign in again — its saved login looks expired. Reconnect \(p.displayName) and retry."
        case .stalled(let p):
            return "\(p.displayName) didn't respond at all — its login is likely expired or it's stuck. Reconnect \(p.displayName) (Providers) and retry."
        }
    }
}

/// A live step emitted WHILE a one-shot call runs, so the meta path can show what a
/// worker is doing in real time instead of a silent multi-minute gap. Only providers
/// with a structured tool stream (Claude, via `--output-format stream-json`) emit these;
/// others complete buffered and emit nothing until they finish.
enum OneShotEvent: Sendable, Equatable {
    case tool(name: String, detail: String?)   // a tool the worker invoked (+ target)
    case fileEdited(String)                     // absolute path of a file it wrote/edited
    case progress(String)                       // a cleaned line of raw output (Codex/Gemini)
}

/// A provider-agnostic single-shot completion. Injectable so the orchestrator can
/// be unit-tested with a mock and run for real with the CLI-backed implementation.
protocol OneShotRunner: Sendable {
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult
    /// Streaming variant: run the call, emitting live tool steps via `onEvent`. Declared
    /// as a REQUIREMENT (not only an extension method) so it dispatches dynamically — an
    /// extension-only method on a protocol existential would always call the default and
    /// silently ignore `CLIOneShotRunner`'s real streaming implementation.
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?,
             onEvent: @escaping @Sendable (OneShotEvent) -> Void) async throws -> OneShotResult
}

extension OneShotRunner {
    /// Default: ignore events and delegate to the buffered `run`, so mocks and any runner
    /// that can't stream keep working unchanged; `CLIOneShotRunner` overrides it.
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?,
             onEvent: @escaping @Sendable (OneShotEvent) -> Void) async throws -> OneShotResult {
        try await run(prompt: prompt, provider: provider, model: model, cwd: cwd)
    }
}

/// The real runner: spawns each provider's CLI headlessly.
struct CLIOneShotRunner: OneShotRunner {
    /// Configured binary names/paths per provider (from AppSettings).
    var binaries: [AIProvider: String] = [:]
    /// Permission mode for the CLIs that support it (Claude). Default read-mostly.
    var permissionMode: String = "acceptEdits"
    /// Optional API keys per provider (from the Keychain). When set for OpenAI, Codex
    /// runs against the API (which re-enables explicit model selection) instead of the
    /// ChatGPT-account default.
    var apiKeys: [AIProvider: String] = [:]
    /// Codex reasoning effort ("" = leave to the account/CLI default).
    var reasoningEffort: String = ""
    /// Read-only: forbid the file-editing tools so this call can READ and run commands
    /// (tests, greps) but never modify the repo. Used by the loop verifier — an
    /// independent judge that can edit the code it's judging (and whose PASS triggers an
    /// auto-merge) is the exact opposite of a verifier.
    var readOnly: Bool = false

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        let configured = binaries[provider] ?? provider.binaryName
        guard let bin = Self.resolveBinary(configured, provider: provider) else {
            throw OneShotError.notInstalled(provider)
        }
        let apiKey = apiKeys[provider].flatMap { $0.isEmpty ? nil : $0 }
        let (args, mode) = Self.command(for: provider, prompt: prompt, model: model,
                                        permissionMode: permissionMode, reasoningEffort: reasoningEffort,
                                        hasAPIKey: apiKey != nil, readOnly: readOnly)
        // Auth/keys travel via the environment, never the argv.
        var extraEnv: [String: String] = [:]
        if provider == .openai, let apiKey { extraEnv["OPENAI_API_KEY"] = apiKey }
        if provider == .gemini {
            if let apiKey { extraEnv["GEMINI_API_KEY"] = apiKey }
            // Otherwise use the Google login the interactive `gemini` sign-in stored:
            // run non-interactively the CLI needs an auth method named explicitly, or
            // it errors ("Please set an Auth method … GOOGLE_GENAI_USE_GCA").
            else { extraEnv["GOOGLE_GENAI_USE_GCA"] = "true" }
        }
        let (out, err, status) = try await Self.launch(bin: bin, args: args, cwd: cwd, extraEnv: extraEnv)
        if status != 0 {
            let msg = err.trimmingCharacters(in: .whitespacesAndNewlines)
            // Record the invocation + stderr so an exported log pinpoints the cause
            // (the CLI's stderr is otherwise lost once the one-line banner is dismissed).
            // The prompt itself is redacted: the diagnostics log is designed to be
            // exported and shared, and the prompt carries the user's conversation.
            let safeArgs = args.map { $0 == prompt ? "<prompt: \($0.count) chars>" : $0 }
            DiagnosticsLog.record("""
                \(provider.displayName) CLI exited \(status)
                cmd: \(bin) \(safeArgs.joined(separator: " "))
                cwd: \(cwd ?? "(none)")
                stderr: \(msg.isEmpty ? "(empty)" : msg)
                stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                """)
            // Google RETIRED the free Gemini CLI for individuals (IneligibleTierError /
            // UNSUPPORTED_CLIENT). "Reconnect" can never fix it — the user must switch to
            // Antigravity (`agy`). Say exactly that instead of the misleading "login expired".
            if provider == .gemini, Self.isAntigravityMigration(out + "\n" + msg) {
                throw OneShotError.failed("Google retired the free Gemini CLI for individuals. Install Antigravity (the `agy` CLI) from https://antigravity.google and sign in there — Coral picks it up automatically — then retry.")
            }
            // A CLI can exit non-zero while printing a structured auth error to STDOUT
            // (Claude prints a 401 result JSON with an empty stderr). Turn that into a
            // typed auth error so any caller can offer a one-tap Reconnect.
            if Self.authFailureMessage(provider: provider, stdout: out, stderr: msg) != nil {
                throw OneShotError.authRequired(provider)
            }
            throw OneShotError.failed(msg.isEmpty ? "\(provider.displayName) exited with code \(status)" : msg)
        }
        switch mode {
        case .claudeJSON:
            guard let parsed = Self.parseClaudeJSON(out, provider: provider, model: model) else {
                throw OneShotError.failed("Couldn't parse \(provider.displayName) output.")
            }
            return parsed
        case .plainText:
            // Codex's plain output and Gemini report no usage, so estimate tokens from the
            // text length and flag it. Cost uses the model's price when we have one (else 0),
            // and is likewise flagged as an estimate.
            let cleanText = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let estTokens = estimateTokens(prompt: prompt, output: cleanText)
            let estCost = Self.estimatedCostUSD(tokens: estTokens, model: model)
            return OneShotResult(text: cleanText, tokens: estTokens, costUSD: estCost,
                                 provider: provider, model: model, estimated: true)
        }
    }

    /// Streaming run. Claude drives the CLI with `--output-format stream-json` over a pipe
    /// and parses each NDJSON line into live tool steps (reusing the chat path's parser).
    /// Codex/Gemini have no structured stream AND block-buffer when their stdout is a pipe,
    /// so they run under a PTY (see `launchPTY`) — that makes them line-buffer, and we
    /// surface each cleaned line as a rolling "what it's doing now". Either way an
    /// interactive auth prompt fails fast (`.authRequired`) instead of hanging.
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?,
             onEvent: @escaping @Sendable (OneShotEvent) -> Void) async throws -> OneShotResult {
        let configured = binaries[provider] ?? provider.binaryName
        guard let bin = Self.resolveBinary(configured, provider: provider) else {
            throw OneShotError.notInstalled(provider)
        }
        let apiKey = apiKeys[provider].flatMap { $0.isEmpty ? nil : $0 }

        // Claude: structured tool stream over a pipe.
        if provider == .claude {
            var args = ["--output-format", "stream-json", "--verbose", "--permission-mode", permissionMode]
            if readOnly { args.append(contentsOf: ["--disallowedTools", "Edit Write MultiEdit NotebookEdit"]) }
            if !model.isEmpty { args.append(contentsOf: ["--model", model]) }
            args.append(contentsOf: ["-p", prompt])
            let acc = StreamAccumulator()
            let (out, err, status) = try await Self.launch(bin: bin, args: args, cwd: cwd, extraEnv: [:]) { line in
                for ev in ClaudeStreamParser.events(from: line) {
                    switch ev {
                    case .tool(let name, let detail): onEvent(.tool(name: name, detail: detail))
                    case .delegated(let sub):         onEvent(.tool(name: "Task", detail: sub))
                    case .skillUsed(let slug):        onEvent(.tool(name: "Skill", detail: slug))
                    case .fileEdited(let path):       onEvent(.fileEdited(path))
                    case .assistantText(let t):       acc.appendText(t)
                    case .usage(let tk, let cost):    acc.setUsage(tokens: tk, cost: cost)
                    default: break
                    }
                }
            }
            if status != 0 {
                let msg = err.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.authFailureMessage(provider: provider, stdout: out, stderr: msg) != nil {
                    throw OneShotError.authRequired(provider)
                }
                throw OneShotError.failed(msg.isEmpty ? "\(provider.displayName) exited with code \(status)" : msg)
            }
            let snap = acc.snapshot()
            return OneShotResult(text: snap.text, tokens: snap.tokens, costUSD: snap.cost,
                                 provider: .claude, model: model)
        }

        // Codex/Gemini: PTY so they stream; each cleaned line becomes rolling progress.
        let args = Self.command(for: provider, prompt: prompt, model: model, permissionMode: permissionMode,
                                reasoningEffort: reasoningEffort, hasAPIKey: apiKey != nil, readOnly: readOnly).args
        var extraEnv: [String: String] = [:]
        if provider == .openai, let apiKey { extraEnv["OPENAI_API_KEY"] = apiKey }
        if provider == .gemini {
            if let apiKey { extraEnv["GEMINI_API_KEY"] = apiKey }
            else { extraEnv["GOOGLE_GENAI_USE_GCA"] = "true" }
        }
        let (out, status) = try await Self.launchPTY(provider: provider, bin: bin, args: args, cwd: cwd,
                                                     extraEnv: extraEnv) { line in
            if let clean = Self.progressLine(line) { onEvent(.progress(clean)) }
        }
        if status != 0 {
            if Self.authFailureMessage(provider: provider, stdout: out, stderr: "") != nil {
                throw OneShotError.authRequired(provider)
            }
            let tail = Self.stripANSI(out).trimmingCharacters(in: .whitespacesAndNewlines)
            throw OneShotError.failed(tail.isEmpty ? "\(provider.displayName) exited with code \(status)" : String(tail.suffix(400)))
        }
        // PTY output carries terminal formatting — strip ANSI for the answer fed to synthesis.
        let cleanText = Self.stripANSI(out).trimmingCharacters(in: .whitespacesAndNewlines)
        let estTokens = estimateTokens(prompt: prompt, output: cleanText)
        let estCost = Self.estimatedCostUSD(tokens: estTokens, model: model)
        return OneShotResult(text: cleanText, tokens: estTokens, costUSD: estCost,
                             provider: provider, model: model, estimated: true)
    }

    /// Remove ANSI/VT100 escape sequences from terminal output.
    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
         .replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
    }

    /// Turn one raw CLI stdout line into a short, human "what's happening now" — or nil to
    /// skip it. Strips ANSI colour codes, drops empty / spinner / pure-symbol / banner
    /// noise, collapses whitespace and truncates. This is the "summarize the important
    /// bit" for providers with no structured tool stream (Codex/Gemini).
    static func progressLine(_ raw: String) -> String? {
        // Strip ANSI escape sequences (colours, cursor moves, spinners).
        let noANSI = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "",
                                              options: .regularExpression)
        let collapsed = noANSI.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let s = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 4 else { return nil }
        // Skip lines that are only symbols/box-drawing/spinner frames (no letters/digits).
        let hasWord = s.range(of: "[\\p{L}\\p{N}]", options: .regularExpression) != nil
        guard hasWord else { return nil }
        // Drop obvious banner/noise lines.
        let low = s.lowercased()
        let noise = ["■", "▔", "────", "====", "thinking...", "loading", "esc to interrupt"]
        if noise.contains(where: { low.contains($0) }) { return nil }
        return s.count > 140 ? String(s.prefix(140)) + "…" : s
    }

    /// Thread-safe accumulator for the streamed answer text + final usage.
    private final class StreamAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var tokens = 0
        private var cost = 0.0
        func appendText(_ t: String) { lock.lock(); if !text.isEmpty { text += "\n" }; text += t; lock.unlock() }
        func setUsage(tokens tk: Int, cost c: Double) { lock.lock(); tokens = tk; cost = c; lock.unlock() }
        func snapshot() -> (text: String, tokens: Int, cost: Double) {
            lock.lock(); defer { lock.unlock() }
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), tokens, cost)
        }
    }

    // MARK: Command building

    enum OutputMode { case claudeJSON, plainText }

    /// The argv (after the binary) and how to read its output, per provider. Flags
    /// go BEFORE the positional prompt (robust across arg parsers).
    static func command(for provider: AIProvider, prompt: String, model: String,
                        permissionMode: String, reasoningEffort: String = "",
                        hasAPIKey: Bool = false, readOnly: Bool = false) -> (args: [String], mode: OutputMode) {
        switch provider {
        case .claude:
            // Claude uses real, full model ids (e.g. claude-opus-4-8).
            var a = ["--output-format", "json", "--permission-mode", permissionMode]
            // Read-only: still allow reads + Bash (to run tests/greps) but forbid every
            // file-editing tool, so a verifier can't modify the repo it's judging.
            if readOnly {
                a.append(contentsOf: ["--disallowedTools", "Edit Write MultiEdit NotebookEdit"])
            }
            if !model.isEmpty { a.append(contentsOf: ["--model", model]) }
            a.append(contentsOf: ["-p", prompt])
            return (a, .claudeJSON)
        case .openai:
            // Codex CLI, non-interactive: `codex exec --skip-git-repo-check "<prompt>"`.
            var a = ["exec", "--skip-git-repo-check"]
            // Reasoning effort works even on a ChatGPT-account login (unlike --model),
            // via a `-c` config override.
            if !reasoningEffort.isEmpty {
                a.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""])
            }
            // Model selection is only accepted with an API key. With a ChatGPT-account
            // login Codex rejects an explicit model ("… not supported when using Codex
            // with a ChatGPT account"), so we omit --model unless a key is configured.
            if hasAPIKey, !model.isEmpty { a.append(contentsOf: ["--model", model]) }
            a.append(prompt)   // --skip-git-repo-check lets it run outside a git repo.
            return (a, .plainText)
        case .gemini:
            // Gemini CLI, non-interactive: `gemini -m <id> -p "<prompt>"`.
            var a: [String] = []
            if !model.isEmpty { a.append(contentsOf: ["-m", model]) }
            a.append(contentsOf: ["-p", prompt])
            return (a, .plainText)
        }
    }

    /// If the CLI output smells like an authentication failure (401 / "failed to
    /// authenticate"), return a per-provider, actionable message; else nil. Coral runs
    /// on each provider's own stored subscription login, so the fix is a re-sign-in.
    /// Google's "the free `gemini` CLI is no longer supported — migrate to Antigravity" error.
    /// A distinct case from a stale login: reconnecting the same CLI can never succeed.
    static func isAntigravityMigration(_ text: String) -> Bool {
        let h = text.lowercased()
        return h.contains("antigravity") || h.contains("ineligibletier")
            || h.contains("unsupported_client")
            || (h.contains("no longer supported") && h.contains("gemini"))
    }

    static func authFailureMessage(provider: AIProvider, stdout: String, stderr: String) -> String? {
        let hay = (stdout + "\n" + stderr).lowercased()
        let looksAuth = hay.contains("401")
            || hay.contains("invalid authentication")
            || hay.contains("failed to authenticate")
            || hay.contains("please set an auth method")
        guard looksAuth else { return nil }
        switch provider {
        case .claude:
            return "Claude couldn't authenticate (401). Coral uses your Claude Code login from its default location — your saved login looks expired. Open Terminal, run `claude`, sign in to your plan, then retry."
        case .openai:
            return "Codex couldn't authenticate. Open Terminal and run `codex login` to sign in to your ChatGPT plan (or add an API key in Connect), then retry."
        case .gemini:
            return "Gemini couldn't authenticate. Open Terminal and run `gemini` to sign in to your Google account (or add an API key in Connect), then retry."
        }
    }

    /// Parse `claude -p --output-format json`'s single result object.
    static func parseClaudeJSON(_ text: String, provider: AIProvider, model: String) -> OneShotResult? {
        guard let data = text.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let result = (obj["result"] as? String) ?? ""
        var tokens = 0
        if let usage = obj["usage"] as? [String: Any] {
            tokens = ((usage["input_tokens"] as? Int) ?? 0)
                + ((usage["output_tokens"] as? Int) ?? 0)
                + ((usage["cache_creation_input_tokens"] as? Int) ?? 0)
                + ((usage["cache_read_input_tokens"] as? Int) ?? 0)
        }
        let cost = (obj["total_cost_usd"] as? Double) ?? 0
        return OneShotResult(text: result, tokens: tokens, costUSD: cost, provider: provider, model: model)
    }

    /// A rough "~$" for an estimated token count: the model's real blended price when we
    /// have one, else a mid-tier fallback. Always an estimate (the caller flags it).
    static func estimatedCostUSD(tokens: Int, model: String) -> Double {
        let perM: Double
        if let price = Constants.pricing[model] {
            perM = (price.inputPerM + price.outputPerM) / 2   // blended: we don't split in/out here
        } else {
            perM = Constants.CostModel.estimatedBlendedFallbackPerM
        }
        return Double(tokens) / 1_000_000 * perM
    }

    // MARK: Process

    /// Build the child environment: an augmented PATH, provider auth keys stripped (so only
    /// what the user configured IN Coral takes effect), the pinned Claude config dir, then
    /// the caller's `extraEnv`. Shared by the pipe and PTY launchers.
    static func buildEnv(bin: String, extraEnv: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let binDir = (bin as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        // An inherited key from the launching shell/Xcode would silently override the
        // subscription login — Claude 401s, Codex is forced into API mode. Strip them all,
        // then re-add the user's own via extraEnv.
        for k in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY",
                  "GEMINI_API_KEY", "GOOGLE_API_KEY",
                  "GOOGLE_GENAI_USE_GCA", "GOOGLE_GENAI_USE_VERTEXAI"] { env[k] = nil }
        if let dir = ClaudeRunner.resolveClaudeConfigDir() { env["CLAUDE_CONFIG_DIR"] = dir }
        for (k, v) in extraEnv { env[k] = v }
        return env
    }

    /// Does this line look like an interactive login/auth prompt the CLI is BLOCKING on?
    /// If so, we kill it immediately and fail with `.authRequired` instead of letting the
    /// run hang until the watchdog — a hung app is the one thing that guarantees no one
    /// uses it. Kept tight to avoid false positives on ordinary model output.
    static func isAuthPrompt(_ line: String) -> Bool {
        let s = line.lowercased()
        return s.contains("opening authentication page")
            || s.contains("do you want to continue")
            || s.contains("please set an auth method")
            || s.contains("waiting for auth")
            || s.contains("authenticate in your browser")
            || s.contains("sign in to continue")
            || s.contains("press enter to continue")
    }

    /// Holds the spawned process so a task cancellation can terminate it (the caller
    /// stops the turn → we must not leave the CLI running, burning tokens/money).
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        private var timedOut = false
        private var auth = false
        private var stalled = false
        private var sawOutput = false
        /// Returns false when the run was already cancelled — the caller must NOT
        /// launch the process then (terminate() on a never-launched Process raises
        /// NSInvalidArgumentException, and launching would leak an ownerless CLI).
        func adopt(_ p: Process) -> Bool { lock.lock(); defer { lock.unlock() }
            if cancelled { return false }
            process = p; return true }
        func terminate() { lock.lock(); defer { lock.unlock() }
            cancelled = true; if let p = process, p.isRunning { p.terminate() } }
        /// The watchdog fired: mark it (so the SIGTERM reads as a timeout, not an opaque
        /// "exited 143") and kill the process.
        func timeOut() { lock.lock(); defer { lock.unlock() }
            timedOut = true; cancelled = true; if let p = process, p.isRunning { p.terminate() } }
        func didTimeOut() -> Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
        /// The CLI printed an interactive auth prompt — kill it now and remember why, so the
        /// caller throws `.authRequired` instead of the run hanging on an unanswerable prompt.
        func tripAuth() { lock.lock(); defer { lock.unlock() }
            auth = true; cancelled = true; if let p = process, p.isRunning { p.terminate() } }
        func didTripAuth() -> Bool { lock.lock(); defer { lock.unlock() }; return auth }
        /// Record that the child has produced at least one byte — cancels the stall watchdog's
        /// grounds for firing.
        func markOutput() { lock.lock(); defer { lock.unlock() }; sawOutput = true }
        /// The stall watchdog fired: if the child is STILL silent, kill it and remember why
        /// (so the caller throws `.stalled`). No-op once any output has arrived.
        func stallIfSilent() { lock.lock(); defer { lock.unlock() }
            guard !sawOutput else { return }
            stalled = true; cancelled = true; if let p = process, p.isRunning { p.terminate() } }
        func didStall() -> Bool { lock.lock(); defer { lock.unlock() }; return stalled }
    }

    /// Launch under a PTY so a CLI that block-buffers when its stdout is a pipe (Codex,
    /// Gemini) instead line-buffers and streams — the only way to see what a non-Claude
    /// worker is doing while it runs. Reads the master fd with raw `read()` (returns 0 at
    /// EOF, -1 on EIO after the child exits — no exceptions, unlike FileHandle). stdout and
    /// stderr are merged onto the PTY; an interactive auth prompt trips a fast fail.
    private static func launchPTY(provider: AIProvider, bin: String, args: [String], cwd: String?,
                                  extraEnv: [String: String],
                                  onOutLine: @escaping @Sendable (String) -> Void) async throws -> (String, Int32) {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, Int32), Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var master: Int32 = -1, slave: Int32 = -1
                    var ws = winsize(ws_row: 48, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
                    guard openpty(&master, &slave, nil, nil, &ws) == 0 else {
                        cont.resume(throwing: OneShotError.failed("Couldn't open a terminal for \(provider.displayName)."))
                        return
                    }
                    // Guarantee BOTH fds are closed on EVERY exit path — a throw during
                    // setup, an auth-trip break, a cancellation, or the normal finish —
                    // instead of relying on each path to remember. `slave` is handed to the
                    // child (we drop our copy once it launches); `master` is ours until the
                    // final read. The flags mark what this closure still owns.
                    var slaveOpen = true, masterOpen = true
                    defer {
                        if slaveOpen { close(slave) }
                        if masterOpen { close(master) }
                    }
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: bin)
                    p.arguments = args
                    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                    p.environment = Self.buildEnv(bin: bin, extraEnv: extraEnv)
                    let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
                    p.standardInput = slaveHandle
                    p.standardOutput = slaveHandle
                    p.standardError = slaveHandle
                    guard box.adopt(p) else {
                        cont.resume(throwing: CancellationError()); return   // defer closes both fds
                    }
                    do { try p.run() } catch {
                        cont.resume(throwing: OneShotError.failed(error.localizedDescription)); return   // defer closes both
                    }
                    close(slave); slaveOpen = false   // the child holds its own copy; the parent reads via master
                    LiveProcesses.register(p)
                    defer { LiveProcesses.deregister(p) }
                    let watchdog = DispatchWorkItem { box.timeOut() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.callTimeout, execute: watchdog)
                    // A PTY worker (Codex/Gemini) streams as it thinks — so producing ZERO bytes
                    // for a whole stall window means it's stuck (almost always an expired login /
                    // hung handshake). Kill it early instead of waiting out the 10-minute cap.
                    let stallWatch = DispatchWorkItem { box.stallIfSilent() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.stallTimeout, execute: stallWatch)
                    let buf = LineBuffer()
                    var outData = Data()
                    var raw = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let n = read(master, &raw, raw.count)
                        if n <= 0 { break }   // 0 = EOF, -1 = EIO after slave close
                        box.markOutput()      // first bytes → the stall watchdog can't fire
                        let chunk = Data(raw[0..<n])
                        outData.append(chunk)
                        var tripped = false
                        for line in buf.append(chunk) {
                            onOutLine(line)
                            if Self.isAuthPrompt(line) { box.tripAuth(); tripped = true }
                        }
                        if tripped { break }
                    }
                    for line in buf.drain() { onOutLine(line) }
                    p.waitUntilExit()
                    watchdog.cancel()
                    stallWatch.cancel()
                    close(master); masterOpen = false
                    // Auth is checked BEFORE timeout: if a stale-login prompt tripped the
                    // fast-fail, surface .authRequired even if the watchdog also fired in the
                    // same window (a killed process can look "timed out"), so the user gets a
                    // one-tap Reconnect rather than a misleading timeout.
                    if box.didTripAuth() { cont.resume(throwing: OneShotError.authRequired(provider)); return }
                    // A silent stall is a faster, more specific signal than the 10-minute cap.
                    if box.didStall() { cont.resume(throwing: OneShotError.stalled(provider)); return }
                    if box.didTimeOut() { cont.resume(throwing: OneShotError.timedOut(Int(Self.callTimeout))); return }
                    cont.resume(returning: (String(data: outData, encoding: .utf8) ?? "", p.terminationStatus))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Per-call watchdog. Generous on purpose: a heavy multi-agent synthesis (the
    /// orchestrator combining many workers' full outputs) legitimately takes minutes —
    /// the former 5-minute cap was killing real syntheses with a SIGTERM (exit 143).
    /// Still a backstop against a genuinely hung CLI.
    static let callTimeout: TimeInterval = 600

    /// First-output stall window for PTY (Codex/Gemini) workers. They stream as they think,
    /// so total silence this long means a stuck login/handshake — fail in ~2 min, not 10.
    /// (Claude uses the pipe path and emits stream-json almost immediately, so this is PTY-only.)
    static let stallTimeout: TimeInterval = 120

    private static func launch(bin: String, args: [String], cwd: String?,
                               extraEnv: [String: String] = [:],
                               onOutLine: (@Sendable (String) -> Void)? = nil) async throws -> (String, String, Int32) {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: bin)
                    p.arguments = args
                    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                    p.environment = Self.buildEnv(bin: bin, extraEnv: extraEnv)
                    let outPipe = Pipe(), errPipe = Pipe()
                    p.standardOutput = outPipe
                    p.standardError = errPipe
                    // Redirect stdin to /dev/null. `codex exec` (and other CLIs) can
                    // hang or misbehave when stdin is a non-TTY pipe with no writer —
                    // openai/codex#20919 — so give them an immediate EOF.
                    p.standardInput = FileHandle.nullDevice
                    guard box.adopt(p) else {
                        cont.resume(throwing: CancellationError()); return
                    }
                    do { try p.run() } catch {
                        DiagnosticsLog.record("Couldn't launch \(bin) (\(args.count) args) — \(error.localizedDescription)")
                        cont.resume(throwing: OneShotError.failed(error.localizedDescription)); return
                    }
                    LiveProcesses.register(p)
                    defer { LiveProcesses.deregister(p) }   // and kill-all-on-quit stops tracking it
                    // Watchdog: a stuck CLI shouldn't hang the turn forever. Terminate
                    // after a generous timeout; a timeout is reported distinctly (below).
                    let watchdog = DispatchWorkItem { box.timeOut() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.callTimeout, execute: watchdog)
                    // Read both pipes concurrently: sequential reads deadlock when
                    // the CLI fills one pipe's ~64KB buffer while we block on the
                    // other (codex and gemini stream progress/spinners to stderr).
                    var errData = Data()
                    let errRead = DispatchGroup()
                    errRead.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        errRead.leave()
                    }
                    // With a line callback (streaming): read stdout incrementally so tool
                    // steps surface AS they happen, still accumulating the full output for
                    // the final parse. Without one: a single blocking read (byte-identical
                    // to the previous behaviour, so the non-streaming path is unchanged).
                    var outData = Data()
                    let outHandle = outPipe.fileHandleForReading
                    if let onOutLine {
                        let buf = LineBuffer()
                        while true {
                            let chunk = outHandle.availableData
                            if chunk.isEmpty { break }   // EOF
                            outData.append(chunk)
                            for line in buf.append(chunk) { onOutLine(line) }
                        }
                        for line in buf.drain() { onOutLine(line) }
                    } else {
                        outData = outHandle.readDataToEndOfFile()
                    }
                    errRead.wait()
                    p.waitUntilExit()
                    watchdog.cancel()
                    // A watchdog kill is a SIGTERM (exit 143) — surface it as a clear
                    // timeout, not the opaque "exited with code 143".
                    if box.didTimeOut() {
                        cont.resume(throwing: OneShotError.timedOut(Int(Self.callTimeout)))
                        return
                    }
                    cont.resume(returning: (String(data: outData, encoding: .utf8) ?? "",
                                            String(data: errData, encoding: .utf8) ?? "",
                                            p.terminationStatus))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Resolve a provider's binary to an absolute path. Uses the SAME robust resolver
    /// that connection detection uses (`ClaudeRunner.resolveBinary`, generic over any
    /// binary name), so a provider that shows "Connected" always launches from the
    /// same path. That resolver validates the result with `isExecutableFile`, so shell
    /// noise (e.g. an interactive `.zshrc` dumping env, yielding junk like "null")
    /// can never be mistaken for a binary — which was the cause of the run launching
    /// a non-existent "null" executable.
    static func resolveBinary(_ configured: String, provider: AIProvider) -> String? {
        let name = configured.isEmpty ? provider.binaryName : configured
        if let p = ClaudeRunner.resolveBinary(name) { return p }
        // Fall back to the provider's alternatives (e.g. Gemini CLI → Antigravity `agy`).
        for alt in provider.alternativeBinaries {
            if let p = ClaudeRunner.resolveBinary(alt) { return p }
        }
        return nil
    }
}
