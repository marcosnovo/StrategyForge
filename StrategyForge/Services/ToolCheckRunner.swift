//
//  ToolCheckRunner.swift
//  StrategyForge
//
//  Runs a team's tool unit tests (article #5). Each check runs a shell command and the
//  PURE `ToolCheckEngine.evaluate` grades the captured output — no model. The command
//  execution is behind an injected `CommandRunner` so `ToolChecks.run` is unit-tested
//  with a mock (the same seam EvalRunner/MetaOrchestrator use).
//

import Foundation

/// Runs a shell command and returns its combined output + exit code. Injectable.
protocol CommandRunner: Sendable {
    func run(_ command: String, cwd: String?) async -> (output: String, exitCode: Int32)
}

enum ToolChecks {
    /// Run every check and grade it. `onProgress(done, total)` fires after each.
    static func run(checks: [ToolCheck], runner: CommandRunner, cwd: String?,
                    onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [ToolCheckResult] {
        var results: [ToolCheckResult] = []
        for (i, check) in checks.enumerated() {
            let (output, exit) = await runner.run(check.command, cwd: cwd)
            results.append(ToolCheckEngine.evaluate(output: output, exitCode: exit, check: check))
            onProgress?(i + 1, checks.count)
        }
        return results
    }
}

/// The real runner: `zsh -lc "<command>"`, combining stdout+stderr, with a timeout so a
/// hung tool can't stall the check. Login shell so the user's PATH/tools resolve.
struct ShellCommandRunner: CommandRunner {
    var timeout: TimeInterval = 30

    func run(_ command: String, cwd: String?) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", command]
                if let cwd, !cwd.isEmpty { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                p.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch {
                    cont.resume(returning: ("couldn't launch: \(error.localizedDescription)", 127))
                    return
                }
                LiveProcesses.register(p)
                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                watchdog.cancel()
                LiveProcesses.deregister(p)
                let out = String(data: data, encoding: .utf8) ?? ""
                cont.resume(returning: (out, p.terminationStatus))
            }
        }
    }
}
