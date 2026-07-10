//
//  CodeGit.swift
//  StrategyForge
//
//  Tiny git helper for Code Mode: compute a unified diff for a file (what changed
//  vs the last commit) and parse it into rendered lines. Runs `git` as a subprocess
//  off the main thread. Returns nil when the folder isn't a git repo or git isn't
//  available — callers then fall back to showing the plain file.
//

import Foundation

struct DiffLine: Identifiable, Hashable {
    enum Kind { case hunk, add, del, context }
    let id = UUID()
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
}

enum CodeGit {

    /// The `git` executable, if present.
    private static func gitPath() -> String? {
        let fm = FileManager.default
        for p in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: p) {
            return p
        }
        return ClaudeRunner.resolveBinary("git")
    }

    /// Unified diff of `file` vs HEAD, parsed. nil if not a repo / no git / no diff.
    nonisolated static func diff(repo: String, file: String) async -> [DiffLine]? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            let out = run(git, ["-C", repo, "diff", "--no-color", "HEAD", "--", file])
            guard let out, !out.isEmpty else { return nil }
            return parse(out)
        }.value
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Parse a unified diff into displayable lines with old/new line numbers.
    static func parse(_ diff: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldNum = 0, newNum = 0
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if raw.hasPrefix("diff --git") || raw.hasPrefix("index ")
                || raw.hasPrefix("--- ") || raw.hasPrefix("+++ ")
                || raw.hasPrefix("new file") || raw.hasPrefix("deleted file")
                || raw.hasPrefix("similarity") || raw.hasPrefix("rename ") {
                continue
            }
            if raw.hasPrefix("@@") {
                // @@ -oldStart,oldLen +newStart,newLen @@
                if let nums = hunkStarts(raw) { oldNum = nums.0; newNum = nums.1 }
                lines.append(DiffLine(kind: .hunk, oldNumber: nil, newNumber: nil, text: raw))
                continue
            }
            if raw.hasPrefix("+") {
                lines.append(DiffLine(kind: .add, oldNumber: nil, newNumber: newNum, text: String(raw.dropFirst())))
                newNum += 1
            } else if raw.hasPrefix("-") {
                lines.append(DiffLine(kind: .del, oldNumber: oldNum, newNumber: nil, text: String(raw.dropFirst())))
                oldNum += 1
            } else {
                let t = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                lines.append(DiffLine(kind: .context, oldNumber: oldNum, newNumber: newNum, text: t))
                oldNum += 1; newNum += 1
            }
        }
        return lines
    }

    private static func hunkStarts(_ header: String) -> (Int, Int)? {
        // e.g. "@@ -12,7 +12,9 @@ func foo()"
        let parts = header.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        func start(_ token: Substring) -> Int? {
            let body = token.dropFirst()                       // drop +/-
            let n = body.split(separator: ",").first ?? body
            return Int(n)
        }
        guard let o = start(parts[1]), let n = start(parts[2]) else { return nil }
        return (o, n)
    }
}
