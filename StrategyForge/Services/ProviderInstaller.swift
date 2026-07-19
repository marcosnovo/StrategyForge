//
//  ProviderInstaller.swift
//  StrategyForge
//
//  One-tap install of a provider's CLI so non-technical users never touch a
//  terminal: the app runs `npm install -g <package>` for them and streams progress.
//  Sign-in is then launched in Terminal (the CLI's own browser OAuth). Non-sandboxed
//  only. If npm/Node isn't present we say so plainly instead of failing silently.
//

import Foundation
import AppKit
import Darwin   // openpty — run CLI logins in a hidden pseudo-terminal (no Terminal window)

enum InstallEvent: Sendable, Equatable {
    case log(String)         // a line of installer output
    case finished            // install completed successfully
    case needsNode           // npm/Node isn't installed — can't proceed automatically
    case needsCode           // the login is waiting for the auth code from the browser
    case failed(String)      // install failed with this message
}

/// Writes the browser auth code back into a running login's (hidden) pseudo-terminal.
/// Claude's `auth login` ends by asking you to paste a code shown in the browser — the
/// sheet collects it and this sends it to the CLI's stdin so the sign-in completes.
final class LoginInput: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    func attach(_ h: FileHandle) { lock.lock(); handle = h; lock.unlock() }
    func submit(_ code: String) {
        lock.lock(); let h = handle; lock.unlock()
        let line = code.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        if let data = line.data(using: .utf8) { try? h?.write(contentsOf: data) }
    }
}

/// Events for the unified connect flow (install if needed → web sign-in).
enum ConnectEvent: Sendable, Equatable {
    enum Step: Sendable, Equatable { case installing, signingIn }
    case phase(Step)
    case log(String)
    case url(String)         // the sign-in URL to open
    case needsCode           // paste the browser's auth code to finish (Claude)
    case needsNode
    case needsTerminal       // this CLI's login must be finished in Terminal
    case failed(String)
    case done
}

enum ProviderInstaller {

    /// Install a provider's CLI globally via npm, streaming progress. Runs the
    /// binary directly (no shell) with an augmented PATH, off the main thread.
    nonisolated static func install(_ provider: AIProvider) -> AsyncStream<InstallEvent> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let npm = ClaudeRunner.resolveBinary("npm") else {
                    continuation.yield(.needsNode)
                    continuation.finish()
                    return
                }

                // Install into a USER-writable prefix (~/.npm-global) so a plain
                // `npm install -g` never hits EACCES on /usr/local/lib (the default
                // global prefix). resolveBinary() already looks in ~/.npm-global/bin.
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let prefix = "\(home)/.npm-global"
                try? FileManager.default.createDirectory(atPath: prefix, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: npm)
                process.arguments = ["install", "-g", "--prefix", prefix, provider.npmInstallSpec]

                var env = ProcessInfo.processInfo.environment
                let binDir = (npm as NSString).deletingLastPathComponent
                env["NPM_CONFIG_PREFIX"] = prefix
                env["PATH"] = "\(binDir):\(prefix)/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env

                let out = Pipe()
                process.standardOutput = out
                process.standardError = out
                let buffer = LineAccumulator()
                out.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    for line in buffer.append(data) { continuation.yield(.log(line)) }
                }

                process.terminationHandler = { proc in
                    out.fileHandleForReading.readabilityHandler = nil
                    for line in buffer.drain() { continuation.yield(.log(line)) }
                    if proc.terminationStatus == 0 {
                        continuation.yield(.finished)
                    } else {
                        continuation.yield(.failed("npm exited with code \(proc.terminationStatus)"))
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    out.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning { process.terminate() }
                }

                do { try process.run() }
                catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    /// Web sign-in WITHOUT a visible Terminal: run the CLI's login command attached to
    /// a HIDDEN pseudo-terminal (so a CLI that insists on a TTY — like `claude auth
    /// login` — behaves normally), stream its output, open the browser URL it prints,
    /// and finish when the OAuth callback completes (the process exits 0). No Terminal
    /// window, no user typing — the app drives the whole thing.
    nonisolated static func signIn(_ provider: AIProvider, input: LoginInput? = nil) -> AsyncStream<InstallEvent> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let parts = provider.loginCommand.split(separator: " ").map(String.init)
                guard let first = parts.first, let bin = ClaudeRunner.resolveBinary(first) else {
                    continuation.yield(.failed("Couldn't find the \(provider.binaryName) CLI — install it first."))
                    continuation.finish(); return
                }
                // A hidden PTY gives the login a real terminal without showing one; a
                // sized window lets a full-screen TUI (Gemini) render + navigate.
                var master: Int32 = 0, slave: Int32 = 0
                var ws = winsize(ws_row: 48, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
                guard openpty(&master, &slave, nil, nil, &ws) == 0 else {
                    continuation.yield(.failed("Couldn't open a login session.")); continuation.finish(); return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: bin)
                process.arguments = Array(parts.dropFirst())
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let binDir = (bin as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):\(home)/.npm-global/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                env["TERM"] = "xterm-256color"
                // Login must write creds to the SAME config dir the app runs from.
                if provider == .claude { ClaudeRunner.sanitizeClaudeAuth(&env) }
                process.environment = env

                let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
                process.standardInput = slaveHandle
                process.standardOutput = slaveHandle
                process.standardError = slaveHandle
                let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
                input?.attach(masterHandle)   // lets the sheet paste the browser code back in

                let buffer = LineAccumulator()
                var openedURL = false
                masterHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                    for line in buffer.append(data) {
                        continuation.yield(.log(line))
                        if !openedURL, let url = firstURL(in: line) {
                            openedURL = true
                            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                            // Claude's login finishes by pasting a code from the browser.
                            if provider == .claude { continuation.yield(.needsCode) }
                        }
                    }
                }
                process.terminationHandler = { proc in
                    masterHandle.readabilityHandler = nil
                    for line in buffer.drain() { continuation.yield(.log(line)) }
                    if proc.terminationStatus == 0 { continuation.yield(.finished) }
                    else { continuation.yield(.failed("Sign-in exited with code \(proc.terminationStatus)")) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    masterHandle.readabilityHandler = nil
                    if process.isRunning { process.terminate() }
                }
                do {
                    try process.run()
                    close(slave)   // the child holds its own copy; the parent doesn't need it
                    // Never hang forever on a login (esp. an interactive TUI that won't exit).
                    DispatchQueue.global().asyncAfter(deadline: .now() + 150) {
                        if process.isRunning { process.terminate() }
                    }
                    // Gemini has no login command: it's a first-run TUI that DOESN'T exit on
                    // success. Nudge past its theme/auth menus (accept the highlighted
                    // "Login with Google") and detect success by the creds file updating.
                    if provider == .gemini {
                        let creds = "\(home)/.gemini/oauth_creds.json"
                        func credsMtime() -> Date? {
                            (try? FileManager.default.attributesOfItem(atPath: creds))?[.modificationDate] as? Date
                        }
                        let before = credsMtime()
                        for delay in [1.2, 2.8, 4.4] {
                            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                try? masterHandle.write(contentsOf: Data("\r".utf8))
                            }
                        }
                        DispatchQueue.global().async {
                            let deadline = Date().addingTimeInterval(140)
                            while Date() < deadline, process.isRunning {
                                Thread.sleep(forTimeInterval: 1.5)
                                if let now = credsMtime(), now != before {
                                    continuation.yield(.finished)
                                    if process.isRunning { process.terminate() }
                                    return
                                }
                            }
                        }
                    }
                } catch {
                    continuation.yield(.failed(error.localizedDescription)); continuation.finish()
                }
            }
        }
    }

    /// The whole "connect" journey as ONE stream: install the CLI if it's missing
    /// (silently, to a user-writable prefix), then run the web sign-in — so a single
    /// Coral flow does everything, no manual Terminal.
    nonisolated static func connect(_ provider: AIProvider, input: LoginInput? = nil) -> AsyncStream<ConnectEvent> {
        AsyncStream { continuation in
            Task.detached {
                // 1. Install only if the CLI can't be found.
                if ClaudeRunner.resolveBinary(provider.binaryName) == nil {
                    continuation.yield(.phase(.installing))
                    var installOK = false
                    for await ev in install(provider) {
                        switch ev {
                        case .log(let l): continuation.yield(.log(l))
                        case .needsNode: continuation.yield(.needsNode); continuation.finish(); return
                        case .failed(let m): continuation.yield(.failed(m)); continuation.finish(); return
                        case .finished: installOK = true
                        case .needsCode: break   // never emitted during install
                        }
                    }
                    guard installOK else { continuation.yield(.failed("Install did not finish")); continuation.finish(); return }
                }
                // 2. Sign-in. Providers whose login is an interactive TUI (Gemini)
                // can't be driven headlessly — hand off to Terminal instead of running
                // a subprocess that would just exit with a nonzero code.
                continuation.yield(.phase(.signingIn))
                if provider.loginNeedsTerminal {
                    await MainActor.run { launchSignIn(provider) }
                    continuation.yield(.needsTerminal)
                    continuation.finish()
                    return
                }
                for await ev in signIn(provider, input: input) {
                    switch ev {
                    case .log(let l):
                        continuation.yield(.log(l))
                        if let u = firstURL(in: l) { continuation.yield(.url(u.absoluteString)) }
                    case .needsCode: continuation.yield(.needsCode)
                    case .needsNode: continuation.yield(.needsNode); continuation.finish(); return
                    case .failed(let m): continuation.yield(.failed(m)); continuation.finish(); return
                    case .finished: continuation.yield(.done); continuation.finish(); return
                    }
                }
                continuation.finish()
            }
        }
    }

    /// The first http(s) URL in a line of CLI output (the OAuth link).
    static func firstURL(in line: String) -> URL? {
        guard let r = line.range(of: "https?://[^\\s\"'<>]+", options: .regularExpression) else { return nil }
        return URL(string: String(line[r]))
    }

    /// Fallback: launch the provider's sign-in in Terminal (for CLIs whose login needs
    /// a real TTY), then the app re-detects the connected CLI.
    @MainActor
    static func launchSignIn(_ provider: AIProvider) {
        // Escape the command for embedding in an AppleScript string literal: backslashes
        // first, then double quotes. loginCommand is a constant today, but escaping keeps
        // this safe if it ever carries a path or flag with a quote.
        let cmd = provider.loginCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(cmd)\"\n" +
                     "tell application \"Terminal\" to activate"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        try? osa.run()
    }
}

/// Line splitter for streamed installer output (drains a trailing partial line).
private final class LineAccumulator: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            if let s = String(data: data[data.startIndex..<nl], encoding: .utf8) { lines.append(s) }
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }
    func drain() -> [String] {
        lock.lock(); defer { lock.unlock() }
        defer { data.removeAll() }
        guard let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [s]
    }
}
