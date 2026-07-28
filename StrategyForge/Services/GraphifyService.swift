//
//  GraphifyService.swift
//  StrategyForge
//
//  Drives the open-source `graphify` CLI (https://graphify.net, Apache-2.0) to turn
//  the active repo into a code knowledge graph, and holds the state the Map section
//  renders. Coral OWNS graphify as a managed dependency: rather than make the user
//  fight pip, it creates its own isolated Python virtual-env under Application Support,
//  installs a PINNED `graphifyy` into it on first use (a one-time "preparing" step),
//  and from then on always invokes THAT interpreter. Nothing pollutes the user's
//  environment; uninstalling is `rm -rf` of the env folder; the version is
//  reproducible. We don't bundle a Python runtime in the .app (that would add
//  100–200MB and hundreds of binaries to notarize) — we lean on the system `python3`
//  (Command Line Tools) and pip the tool in once.
//
//  Light mode by default (`graphify <repo>` — deterministic tree-sitter over code,
//  token-cheap); `--mode deep` is opt-in and additionally spends Claude tokens. The
//  same `CLAUDE_CONFIG_DIR` the chat path pins is exported so deep-mode Claude calls
//  use the login Coral is signed into. Reuses Coral's hardened process plumbing
//  (`ClaudeRunner.resolveBinary`, the `LiveProcesses` kill-on-quit registry).
//

import Foundation

/// Where the Map feature is in its lifecycle. Drives which UI state shows.
enum GraphifyPhase: Equatable {
    case idle          // ready (or not yet run) — a build can be kicked off
    case needsPython   // no system python3 (Command Line Tools) to build the env with
    case preparing     // one-time: creating the venv + pip-installing graphify
    case cloning       // shallow-cloning a GitHub repo before mapping it
    case running       // building the graph
    case done          // graph parsed and ready
    case failed(String)
}

@MainActor
@Observable
final class CodeMapStore {
    /// The repo to map. Set from the picker, a GitHub clone, or the active chat's repo.
    var repoURL: URL?
    /// Bound to the "from GitHub" field — a URL or `owner/repo` shorthand.
    var gitHubInput = ""

    private(set) var phase: GraphifyPhase = .idle
    private(set) var graph: CodeGraph?
    /// graphify's own interactive visualisation, opened on demand in a WKWebView.
    private(set) var htmlURL: URL?
    /// Wall-clock of the last successful build (repo path → done), for the header.
    private(set) var lastBuiltRepo: String?

    /// The exact `graphifyy` release Coral manages — pinned so a map is reproducible and
    /// an upstream change can't silently alter output. `[leiden]` pulls the community
    /// detection that makes clusters meaningful.
    private static let pinnedRequirement = "graphifyy[leiden]==0.9.29"

    /// True when a build can be kicked off right now.
    var canRun: Bool {
        repoURL != nil && phase != .running && phase != .preparing && phase != .cloning
    }

    /// Whether Coral's managed graphify is already installed (no work, no network).
    var isReady: Bool { Self.managedGraphify() != nil }

    /// Reconcile phase with what's on disk WITHOUT doing any work: managed env present →
    /// idle; else if there's no python3 to build it with → needsPython; else idle (the
    /// env is bootstrapped lazily on the first build).
    func refreshReadiness() {
        if Self.managedGraphify() != nil {
            if phase == .needsPython { phase = .idle }
        } else if Self.systemPython() == nil {
            phase = .needsPython
        } else if phase == .needsPython {
            phase = .idle
        }
    }

    /// Trigger the one-time Command Line Tools installer (which provides python3) when
    /// it's missing. Best-effort: macOS shows its own GUI prompt.
    func installCommandLineTools() {
        guard let xcs = ClaudeRunner.resolveBinary("xcode-select") else { return }
        Task { _ = await Self.launch(bin: xcs, args: ["--install"], cwd: nil) }
    }

    /// Build (or rebuild) the graph for `repoURL`, bootstrapping the managed env first if
    /// needed. graphify caches by content hash, so a re-run on an unchanged repo is fast.
    func run() async {
        guard let repo = repoURL else { return }
        guard await ensureReady() else { return }
        guard let bin = Self.managedGraphify() else { phase = .needsPython; return }
        phase = .running
        graph = nil

        // `graphify update <repo>` is the deterministic, tree-sitter-only, NO-LLM build —
        // token-free and the right default. (Deep prose/PDF/image extraction is graphify's
        // agent-skill flow, not a CLI flag, so it's a later enhancement.) graphify writes
        // its output into `graphify-out/` under the working directory, so cwd = the repo.
        let result = await Self.launch(bin: bin, args: ["update", repo.path], cwd: repo.path)

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
        // No parseable JSON, but if graphify at least produced the HTML that's still a win.
        if htmlURL != nil {
            lastBuiltRepo = repo.path
            phase = .done
            return
        }
        if result.status != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            DiagnosticsLog.record("""
                graphify update exited \(result.status)
                repo: \(repo.path)
                stderr: \(msg.isEmpty ? "(empty)" : String(msg.prefix(800)))
                """)
            phase = .failed(msg.isEmpty ? "graphify exited with code \(result.status)." : msg)
        } else {
            phase = .failed("graphify finished but wrote no readable graph.json.")
        }
    }

    /// True when a GitHub clone can be started.
    var canClone: Bool {
        !gitHubInput.trimmingCharacters(in: .whitespaces).isEmpty
            && phase != .running && phase != .preparing && phase != .cloning
    }

    /// Clone a GitHub repo (shallow, into a Coral-managed folder) and map it — so you can
    /// map any repo without having it checked out locally. Accepts a full URL or `owner/repo`.
    /// Private repos rely on the user's existing git credentials/SSH.
    func cloneAndMap() async {
        let raw = gitHubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let (owner, repo) = Self.parseOwnerRepo(raw) else {
            phase = .failed("That doesn't look like a GitHub repo (use a URL or owner/repo)."); return
        }
        guard await ensureReady() else { return }   // managed graphify must exist to map afterwards
        guard let git = ClaudeRunner.resolveBinary("git") else {
            phase = .failed("git isn't available — install Apple's Command Line Tools."); return
        }
        let dest = Self.reposRoot().appendingPathComponent("\(owner)-\(repo)", isDirectory: true)
        let fm = FileManager.default
        phase = .cloning

        if fm.fileExists(atPath: dest.appendingPathComponent(".git").path) {
            // Already cloned once — fast-forward it, best-effort, then re-map.
            _ = await Self.launch(bin: git, args: ["-C", dest.path, "pull", "--ff-only"], cwd: nil, timeout: 300)
        } else {
            try? fm.createDirectory(at: Self.reposRoot(), withIntermediateDirectories: true)
            let url = Self.normalizedCloneURL(raw, owner: owner, repo: repo)
            let clone = await Self.launch(bin: git, args: ["clone", "--depth", "1", url, dest.path],
                                          cwd: nil, timeout: 600)
            guard clone.status == 0, fm.fileExists(atPath: dest.path) else {
                let msg = clone.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = .failed(msg.isEmpty ? "git clone failed." : String(msg.suffix(500)))
                return
            }
        }
        repoURL = dest
        await run()
    }

    /// Extract (owner, repo) from a GitHub URL or `owner/repo` shorthand; nil if it doesn't fit.
    static func parseOwnerRepo(_ s: String) -> (String, String)? {
        var t = s.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "git@github.com:", with: "")
        if let r = t.range(of: "github.com/") { t = String(t[r.upperBound...]) }
        if t.hasSuffix(".git") { t = String(t.dropLast(4)) }
        let parts = t.split(separator: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func normalizedCloneURL(_ raw: String, owner: String, repo: String) -> String {
        (raw.contains("github.com") || raw.hasPrefix("git@")) ? raw
            : "https://github.com/\(owner)/\(repo).git"
    }

    /// Coral-managed home for cloned repos: Application Support/Coral/repos.
    private static func reposRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Coral/repos", isDirectory: true)
    }

    // MARK: - Managed environment (bootstrap)

    /// Ensure the managed graphify is installed; create the venv + pip-install it on the
    /// first call. Returns false (and sets a phase explaining why) when it can't.
    private func ensureReady() async -> Bool {
        if Self.managedGraphify() != nil { return true }
        guard let python = Self.systemPython() else { phase = .needsPython; return false }

        phase = .preparing
        let root = Self.envRoot()
        let venv = Self.venvDir()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 1) Create the isolated virtual-env (skip if a half-built one already has python).
        if !FileManager.default.isExecutableFile(atPath: Self.venvPython().path) {
            let mk = await Self.launch(bin: python, args: ["-m", "venv", venv.path], cwd: nil, timeout: 300)
            guard mk.status == 0, FileManager.default.isExecutableFile(atPath: Self.venvPython().path) else {
                let msg = mk.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                // A stub python3 (no Command Line Tools) fails here — steer the user there.
                if msg.contains("xcode-select") || msg.contains("Command Line") || mk.status == 72 {
                    phase = .needsPython
                } else {
                    phase = .failed(msg.isEmpty ? "Couldn't create the Python environment." : msg)
                }
                return false
            }
        }

        // 2) Pip-install the pinned graphify into the env (upgrade pip first for wheels).
        let vpy = Self.venvPython().path
        _ = await Self.launch(bin: vpy, args: ["-m", "pip", "install", "--upgrade", "pip"], cwd: nil, timeout: 300)
        let install = await Self.launch(bin: vpy,
                                        args: ["-m", "pip", "install", Self.pinnedRequirement],
                                        cwd: nil, timeout: 900)
        guard Self.managedGraphify() != nil else {
            let msg = install.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            DiagnosticsLog.record("graphify install failed (\(install.status)): \(String(msg.prefix(800)))")
            phase = .failed(msg.isEmpty ? "Couldn't install graphify into Coral's environment." : String(msg.suffix(600)))
            return false
        }
        return true
    }

    // MARK: - Paths / binary resolution

    /// Application Support/Coral/graphify — Coral's private home for the managed env.
    private static func envRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Coral/graphify", isDirectory: true)
    }
    private static func venvDir() -> URL { envRoot().appendingPathComponent("venv", isDirectory: true) }
    private static func venvPython() -> URL { venvDir().appendingPathComponent("bin/python") }

    /// The managed `graphify` console script, if it's installed and executable.
    private static func managedGraphify() -> String? {
        let path = venvDir().appendingPathComponent("bin/graphify").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// A system python3 to build the env with (Command Line Tools). nil → we can't.
    private static func systemPython() -> String? {
        ClaudeRunner.resolveBinary("python3")
    }

    // MARK: - Process

    private struct RunResult { var stdout: String; var stderr: String; var status: Int32 }

    /// Launch a CLI headlessly and collect its output. Nonisolated: the blocking process
    /// work runs off the main actor; the caller (MainActor) just awaits the result.
    private nonisolated static func launch(bin: String, args: [String], cwd: String?,
                                           timeout: TimeInterval = 600) async -> RunResult {
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
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

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
