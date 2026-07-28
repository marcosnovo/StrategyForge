//
//  GraphifyService.swift
//  StrategyForge
//
//  Drives the open-source `graphify` CLI (https://graphify.net) to turn the active
//  repo into a code knowledge graph, and holds the state the Map section renders.
//  Graphify is a Python tool (`pipx install graphifyy`); we DETECT it, optionally
//  INSTALL it on explicit intent, RUN it in the repo (light mode by default so it
//  stays token-cheap — deterministic tree-sitter only; `--mode deep` is opt-in and
//  additionally spends Claude tokens reading prose/images), then read the
//  `graphify-out/graph.json` it writes and parse it into a `CodeGraph`. Coral never
//  reimplements the parsing — it's the beautiful native vessel + a link to
//  graphify's own interactive `graph.html`.
//
//  Reuses Coral's hardened process plumbing: `ClaudeRunner.resolveBinary` (validates
//  the path is really executable, so shell noise can't be mistaken for a binary) and
//  the `LiveProcesses` registry (so a long graph build is killed on quit, not
//  orphaned). The same `CLAUDE_CONFIG_DIR` the chat path pins is exported, so
//  graphify's deep-mode Claude calls use the exact login Coral is signed into.
//

import Foundation

/// Where the Map feature is in its lifecycle. Drives which UI state shows.
enum GraphifyPhase: Equatable {
    case idle          // nothing run yet this session
    case notInstalled  // the `graphify` CLI isn't on PATH
    case installing    // pipx/pip install in flight
    case running       // building the graph
    case done          // graph parsed and ready
    case failed(String)
}

@MainActor
@Observable
final class CodeMapStore {
    /// The repo to map. Set from the picker or pre-filled from the active chat's repo.
    var repoURL: URL?
    /// Deep mode adds prose/PDF/image concept extraction (spends Claude tokens). Off by
    /// default so a run is deterministic tree-sitter over code and effectively free.
    var deep = false

    private(set) var phase: GraphifyPhase = .idle
    private(set) var graph: CodeGraph?
    /// graphify's own interactive visualisation, opened on demand in a WKWebView.
    private(set) var htmlURL: URL?
    /// Wall-clock of the last successful build (repo path → done), for the header.
    private(set) var lastBuiltRepo: String?

    /// True when a build can be kicked off right now.
    var canRun: Bool {
        repoURL != nil && phase != .running && phase != .installing
    }

    /// Detect whether the `graphify` CLI is available, WITHOUT running anything. Leaves
    /// `phase` at `.notInstalled` when absent so the section can offer to install it;
    /// otherwise leaves the current phase untouched (idle/done).
    func refreshInstalled() {
        if Self.graphifyBinary() == nil {
            phase = .notInstalled
        } else if phase == .notInstalled {
            phase = .idle
        }
    }

    /// Best-effort install of the CLI on explicit user intent. Prefers `pipx` (isolated
    /// env — the tool's own recommendation), falls back to `pip3 --user`.
    func install() async {
        guard phase != .installing, phase != .running else { return }
        phase = .installing
        let (bin, args): (String, [String])
        if let pipx = ClaudeRunner.resolveBinary("pipx") {
            (bin, args) = (pipx, ["install", "graphifyy"])
        } else if let pip = ClaudeRunner.resolveBinary("pip3") ?? ClaudeRunner.resolveBinary("pip") {
            (bin, args) = (pip, ["install", "--user", "graphifyy"])
        } else {
            phase = .failed(installHint)
            return
        }
        let result = await Self.launch(bin: bin, args: args, cwd: nil)
        if result.status == 0, Self.graphifyBinary() != nil {
            phase = .idle
        } else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .failed(msg.isEmpty ? installHint : msg)
        }
    }

    /// Build (or rebuild) the graph for `repoURL`. graphify caches by content hash, so a
    /// re-run on an unchanged repo is fast.
    func run() async {
        guard let repo = repoURL else { return }
        guard let bin = Self.graphifyBinary() else { phase = .notInstalled; return }
        phase = .running
        graph = nil

        // Light by default (`graphify <repo>`); deep adds `--mode deep`. graphify writes
        // its output into `graphify-out/` under the working directory, so cwd = the repo.
        var args = [repo.path]
        if deep { args.append(contentsOf: ["--mode", "deep"]) }

        let result = await Self.launch(bin: bin, args: args, cwd: repo.path)

        let outDir = repo.appendingPathComponent("graphify-out", isDirectory: true)
        let jsonURL = outDir.appendingPathComponent("graph.json")
        let html = outDir.appendingPathComponent("graph.html")
        htmlURL = FileManager.default.fileExists(atPath: html.path) ? html : nil

        if let data = try? Data(contentsOf: jsonURL), let parsed = CodeGraph.parse(data) {
            graph = parsed
            lastBuiltRepo = repo.path
            phase = .done
            return
        }

        // No parseable JSON. If graphify at least produced the HTML, that's still a win —
        // the user can open the interactive view; otherwise surface the CLI's own error.
        if htmlURL != nil {
            lastBuiltRepo = repo.path
            phase = .done
            return
        }
        if result.status != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            DiagnosticsLog.record("""
                graphify exited \(result.status)
                repo: \(repo.path)  deep: \(deep)
                stderr: \(msg.isEmpty ? "(empty)" : String(msg.prefix(800)))
                """)
            phase = .failed(msg.isEmpty ? "graphify exited with code \(result.status)." : msg)
        } else {
            phase = .failed("graphify finished but wrote no readable graph.json.")
        }
    }

    /// A short, copyable hint for manual install when neither pipx nor pip is found.
    let installHint = "Install it with:  pipx install graphifyy   (or)   pip3 install graphifyy"

    // MARK: - Binary resolution

    /// The `graphify` executable, or nil when it isn't installed.
    private static func graphifyBinary() -> String? {
        ClaudeRunner.resolveBinary("graphify")
    }

    // MARK: - Process

    private struct RunResult { var stdout: String; var stderr: String; var status: Int32 }

    /// Generous backstop for a big repo's first build (subsequent runs hit graphify's
    /// content cache). Mirrors the one-shot runner's watchdog budget.
    private static let timeout: TimeInterval = 600

    /// Launch a CLI headlessly and collect its output. Nonisolated: the blocking process
    /// work runs off the main actor; the caller (MainActor) just awaits the result.
    private nonisolated static func launch(bin: String, args: [String], cwd: String?) async -> RunResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = args
                if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let binDir = (bin as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                // graphify's deep mode calls Claude — pin the same config dir the chat uses
                // so it authenticates with the login Coral is signed into.
                if let dir = ClaudeRunner.resolveClaudeConfigDir() { env["CLAUDE_CONFIG_DIR"] = dir }
                p.environment = env

                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice

                do { try p.run() } catch {
                    cont.resume(returning: RunResult(stdout: "", stderr: error.localizedDescription, status: -1))
                    return
                }
                LiveProcesses.register(p)
                defer { LiveProcesses.deregister(p) }

                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: watchdog)

                // Drain both pipes concurrently so a full stderr buffer can't deadlock stdout.
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

                cont.resume(returning: RunResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    status: p.terminationStatus))
            }
        }
    }
}
