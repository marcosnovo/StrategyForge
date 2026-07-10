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

    var errorDescription: String? {
        switch self {
        case .notInstalled(let p): return "\(p.displayName)'s CLI isn't installed. Connect it in Connect first."
        case .failed(let m): return m
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

    func run(prompt: String, provider: AIProvider, model: String, cwd: String?) async throws -> OneShotResult {
        let configured = binaries[provider] ?? provider.binaryName
        guard let bin = Self.resolveBinary(configured, provider: provider) else {
            throw OneShotError.notInstalled(provider)
        }
        let (args, mode) = Self.command(for: provider, prompt: prompt, model: model, permissionMode: permissionMode)
        let (out, err, status) = try await Self.launch(bin: bin, args: args, cwd: cwd)
        if status != 0 {
            let msg = err.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// The argv (after the binary) and how to read its output, per provider.
    static func command(for provider: AIProvider, prompt: String, model: String,
                        permissionMode: String) -> (args: [String], mode: OutputMode) {
        switch provider {
        case .claude:
            var a = ["-p", prompt, "--output-format", "json", "--permission-mode", permissionMode]
            if !model.isEmpty { a.append(contentsOf: ["--model", model]) }
            return (a, .claudeJSON)
        case .openai:
            // Codex CLI, non-interactive.
            var a = ["exec", prompt]
            if !model.isEmpty { a.append(contentsOf: ["--model", model]) }
            return (a, .plainText)
        case .gemini:
            var a = ["-p", prompt]
            if !model.isEmpty { a.append(contentsOf: ["-m", model]) }
            return (a, .plainText)
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
        func adopt(_ p: Process) { lock.lock(); defer { lock.unlock() }
            if cancelled { p.terminate() } else { process = p } }
        func terminate() { lock.lock(); defer { lock.unlock() }
            cancelled = true; if let p = process, p.isRunning { p.terminate() } }
    }

    private static func launch(bin: String, args: [String], cwd: String?) async throws -> (String, String, Int32) {
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
                    p.environment = env
                    let outPipe = Pipe(), errPipe = Pipe()
                    p.standardOutput = outPipe
                    p.standardError = errPipe
                    box.adopt(p)
                    do { try p.run() } catch {
                        cont.resume(throwing: OneShotError.failed(error.localizedDescription)); return
                    }
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
                    cont.resume(returning: (String(data: outData, encoding: .utf8) ?? "",
                                            String(data: errData, encoding: .utf8) ?? "",
                                            p.terminationStatus))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Resolve a provider's binary to an absolute path. Reuses Claude's richer
    /// lookup; for others, an interactive-login-shell `command -v`.
    static func resolveBinary(_ configured: String, provider: AIProvider) -> String? {
        if provider == .claude { return ClaudeRunner.resolveBinary(configured) }
        let fm = FileManager.default
        let name = configured.isEmpty ? provider.binaryName : configured
        if name.hasPrefix("/"), fm.isExecutableFile(atPath: name) { return name }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "command -v \"$SF_PROVIDER_BIN\""]
        var env = ProcessInfo.processInfo.environment
        env["SF_PROVIDER_BIN"] = name
        p.environment = env
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return (path?.isEmpty == false) ? path : nil
    }
}
