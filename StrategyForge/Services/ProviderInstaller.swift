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

enum InstallEvent: Sendable, Equatable {
    case log(String)         // a line of installer output
    case finished            // install completed successfully
    case needsNode           // npm/Node isn't installed — can't proceed automatically
    case failed(String)      // install failed with this message
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

                let process = Process()
                process.executableURL = URL(fileURLWithPath: npm)
                process.arguments = ["install", "-g", provider.npmPackage]

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let binDir = (npm as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
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

    /// Launch the provider's sign-in in Terminal so the browser OAuth completes,
    /// then the app re-detects the connected CLI.
    @MainActor
    static func launchSignIn(_ provider: AIProvider) {
        let cmd = provider.loginCommand
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
