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

/// The result of a single model call.
struct OneShotResult: Sendable, Equatable {
    var text: String
    var tokens: Int
    var costUSD: Double
    var provider: AIProvider
    var model: String
}

enum OneShotError: Error, LocalizedError, Equatable {
    case notInstalled(AIProvider)
    case failed(String)
    /// The watchdog terminated the call after N seconds — reported distinctly so the
    /// user sees a timeout (and its cause) rather than an opaque "exited with code 143".
    case timedOut(Int)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let p): return "\(p.displayName)'s CLI isn't installed. Connect it in Connect first."
        case .failed(let m): return m
        case .timedOut(let s):
            return "The model didn't finish within \(s / 60) minutes — the task or the combined agent output may be too large. Try splitting the task, using fewer agents, or a faster model."
        }
    }
}

/// A provider-agnostic single-shot completion. Injectable so the orchestrator can
/// be unit-tested with a mock and run for real with the CLI-backed implementation.
protocol OneShotRunner: Sendable {
    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult
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

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        let configured = binaries[provider] ?? provider.binaryName
        guard let bin = Self.resolveBinary(configured, provider: provider) else {
            throw OneShotError.notInstalled(provider)
        }
        let apiKey = apiKeys[provider].flatMap { $0.isEmpty ? nil : $0 }
        let (args, mode) = Self.command(for: provider, prompt: prompt, model: model,
                                        permissionMode: permissionMode, reasoningEffort: reasoningEffort,
                                        hasAPIKey: apiKey != nil)
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
            // A CLI can exit non-zero while printing a structured auth error to STDOUT
            // (Claude prints a 401 result JSON with an empty stderr). Turn that into a
            // message the user can act on instead of a bare "exited with code N".
            if let friendly = Self.authFailureMessage(provider: provider, stdout: out, stderr: msg) {
                throw OneShotError.failed(friendly)
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
            return OneShotResult(text: out.trimmingCharacters(in: .whitespacesAndNewlines),
                                 tokens: 0, costUSD: 0, provider: provider, model: model)
        }
    }

    // MARK: Command building

    enum OutputMode { case claudeJSON, plainText }

    /// The argv (after the binary) and how to read its output, per provider. Flags
    /// go BEFORE the positional prompt (robust across arg parsers).
    static func command(for provider: AIProvider, prompt: String, model: String,
                        permissionMode: String, reasoningEffort: String = "",
                        hasAPIKey: Bool = false) -> (args: [String], mode: OutputMode) {
        switch provider {
        case .claude:
            // Claude uses real, full model ids (e.g. claude-opus-4-8).
            var a = ["--output-format", "json", "--permission-mode", permissionMode]
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

    // MARK: Process

    /// Holds the spawned process so a task cancellation can terminate it (the caller
    /// stops the turn → we must not leave the CLI running, burning tokens/money).
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        private var timedOut = false
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
    }

    /// Per-call watchdog. Generous on purpose: a heavy multi-agent synthesis (the
    /// orchestrator combining many workers' full outputs) legitimately takes minutes —
    /// the former 5-minute cap was killing real syntheses with a SIGTERM (exit 143).
    /// Still a backstop against a genuinely hung CLI.
    static let callTimeout: TimeInterval = 600

    private static func launch(bin: String, args: [String], cwd: String?,
                               extraEnv: [String: String] = [:]) async throws -> (String, String, Int32) {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: bin)
                    p.arguments = args
                    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                    var env = ProcessInfo.processInfo.environment
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let binDir = (bin as NSString).deletingLastPathComponent
                    env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                    // Only credentials the user configured IN Coral should take effect.
                    // An inherited key from the launching shell/Xcode would silently
                    // override the subscription login — Claude 401s, Codex is forced into
                    // API mode. Strip them all, then re-add the user's own via extraEnv.
                    for k in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY",
                              "GEMINI_API_KEY", "GOOGLE_API_KEY",
                              "GOOGLE_GENAI_USE_GCA", "GOOGLE_GENAI_USE_VERTEXAI"] { env[k] = nil }
                    // Pin the SAME Claude config dir the chat path uses, so diagnostics
                    // and the real run never disagree about which login they test.
                    if let dir = ClaudeRunner.resolveClaudeConfigDir() { env["CLAUDE_CONFIG_DIR"] = dir }
                    for (k, v) in extraEnv { env[k] = v }
                    p.environment = env
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
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
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
        return ClaudeRunner.resolveBinary(name)
    }
}
