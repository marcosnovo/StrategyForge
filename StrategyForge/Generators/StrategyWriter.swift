//
//  StrategyWriter.swift
//  StrategyForge
//
//  Disk I/O layer around the pure generators. Handles previewing (merging the
//  managed CLAUDE.md section against whatever is currently on disk), detecting
//  overwrites, and writing safely.
//
//  Safety rules:
//   • Only ever writes `.claude/agents/*.md` and the repo-root CLAUDE.md.
//   • Never deletes files — regeneration overwrites the current strategy's files
//     but leaves any other files (including stale agents) untouched.
//   • CLAUDE.md is merged, never clobbered: only the marked section changes.
//

import Foundation

struct StrategyWriter {
    let repoURL: URL
    var binary: String = "claude"

    private var fm: FileManager { .default }

    // MARK: - Preview

    /// All files that would be written, with exact contents, WITHOUT touching disk.
    /// The CLAUDE.md preview reflects a merge against the file currently on disk.
    func previewFiles(for strategy: Strategy) -> [GeneratedFile] {
        var files = AgentFileGenerator.generate(for: strategy)
        let existing = try? String(contentsOf: claudeMdURL, encoding: .utf8)
        let merged = ClaudeMdGenerator.merged(existing: existing, strategy: strategy, binary: binary)
        files.append(GeneratedFile(relativePath: ClaudeMdGenerator.fileName, contents: merged))
        return files
    }

    /// Relative paths of files that already exist on disk and would be overwritten.
    /// (CLAUDE.md is always merged rather than clobbered, so it is not a conflict.)
    func existingAgentConflicts(for strategy: Strategy) -> [String] {
        AgentFileGenerator.generate(for: strategy)
            .filter { fm.fileExists(atPath: repoURL.appendingPathComponent($0.relativePath).path) }
            .map(\.relativePath)
    }

    // MARK: - Write

    /// Write the agent files and merge the CLAUDE.md section. Returns the relative
    /// paths written, in order. Throws on any filesystem error.
    @discardableResult
    func write(strategy: Strategy) throws -> [String] {
        var written: [String] = []

        // 1. Subagent files.
        let agentsDir = repoURL.appendingPathComponent(AgentFileGenerator.agentsDirectory, isDirectory: true)
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        for file in AgentFileGenerator.generate(for: strategy) {
            let url = repoURL.appendingPathComponent(file.relativePath)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
            written.append(file.relativePath)
        }

        // 2. CLAUDE.md — merge into whatever exists.
        let existing = try? String(contentsOf: claudeMdURL, encoding: .utf8)
        let merged = ClaudeMdGenerator.merged(existing: existing, strategy: strategy, binary: binary)
        try merged.write(to: claudeMdURL, atomically: true, encoding: .utf8)
        written.append(ClaudeMdGenerator.fileName)

        return written
    }

    // MARK: - Paths

    private var claudeMdURL: URL {
        repoURL.appendingPathComponent(ClaudeMdGenerator.fileName)
    }
}
