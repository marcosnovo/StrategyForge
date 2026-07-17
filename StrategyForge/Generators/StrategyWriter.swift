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
//   • Deletes ONLY agent files it previously generated (managed-signature) that are
//     no longer part of the strategy; hand-written agent files are never touched.
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
        if let mcp = McpConfigGenerator.json(for: strategy.mcpServers) {
            files.append(GeneratedFile(relativePath: McpConfigGenerator.fileName, contents: mcp))
        }
        return files
    }

    /// A pre-write diff for every file that would be written: created vs. modified
    /// vs. unchanged, with the line-by-line changes, WITHOUT touching disk (reads
    /// existing contents only). The CLAUDE.md diff reflects the managed-section merge.
    func previewDiffs(for strategy: Strategy) -> [FileDiff] {
        var diffs = previewFiles(for: strategy).map { file in
            let existing = try? String(contentsOf: repoURL.appendingPathComponent(file.relativePath),
                                       encoding: .utf8)
            return FileDiff.make(file: file, existing: existing)
        }
        // Deletions: write() prunes managed agent files that dropped out of the
        // strategy (renamed/removed roles). Surface them so the diff the user
        // approves matches exactly what write() does.
        for rel in prunedAgentPaths(for: strategy) {
            let existing = try? String(contentsOf: repoURL.appendingPathComponent(rel), encoding: .utf8)
            diffs.append(FileDiff.deleted(relativePath: rel, existing: existing))
        }
        return diffs
    }

    /// Managed agent files we previously generated that are no longer part of the
    /// strategy. `write()` deletes exactly these; the preview uses the same list so
    /// the two never diverge. Only files bearing our managed signature qualify —
    /// hand-written agent files are never included.
    func prunedAgentPaths(for strategy: Strategy) -> [String] {
        let agentsDir = repoURL.appendingPathComponent(AgentFileGenerator.agentsDirectory, isDirectory: true)
        let newPaths = Set(AgentFileGenerator.generate(for: strategy).map(\.relativePath))
        guard let entries = try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var pruned: [String] = []
        for entry in entries where entry.pathExtension == "md" {
            // The loop verifier carries the same managed signature but belongs to the
            // Loops feature (LoopFileGenerator) — writing a team must not dismantle a
            // configured loop, so it is never pruned here.
            if entry.lastPathComponent == "loop-verifier.md" { continue }
            let rel = "\(AgentFileGenerator.agentsDirectory)/\(entry.lastPathComponent)"
            guard !newPaths.contains(rel),
                  let content = try? String(contentsOf: entry, encoding: .utf8),
                  content.contains(AgentFileGenerator.managedSignature)
                    || content.contains(AgentFileGenerator.legacyManagedSignature) else { continue }
            pruned.append(rel)
        }
        return pruned
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
        let generated = AgentFileGenerator.generate(for: strategy)

        // Prune stale agents WE previously generated (renamed/removed roles) so they
        // don't linger as active subagents. Uses the SAME list the preview diff
        // surfaces (prunedAgentPaths), so what the user approved is what happens.
        // Only files bearing our managed signature are ever removed.
        for rel in prunedAgentPaths(for: strategy) {
            try? fm.removeItem(at: repoURL.appendingPathComponent(rel))
        }

        for file in generated {
            let url = repoURL.appendingPathComponent(file.relativePath)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
            written.append(file.relativePath)
        }

        // 2. CLAUDE.md — merge into whatever exists.
        let existing = try? String(contentsOf: claudeMdURL, encoding: .utf8)
        let merged = ClaudeMdGenerator.merged(existing: existing, strategy: strategy, binary: binary)
        try merged.write(to: claudeMdURL, atomically: true, encoding: .utf8)
        written.append(ClaudeMdGenerator.fileName)

        // 2b. Skills — copy each attached skill folder into the repo's .claude/skills
        // so Claude Code discovers it. A slug already present in the repo is left as
        // is; otherwise it's copied from the personal store (~/.claude/skills).
        for slug in strategy.skills {
            let dest = repoURL.appendingPathComponent(".claude/skills/\(slug)", isDirectory: true)
            if fm.fileExists(atPath: dest.path) { continue }
            let source = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/skills/\(slug)", isDirectory: true)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: source, to: dest)
            written.append(".claude/skills/\(slug)")
        }

        // 3. .mcp.json — external tool servers Claude Code auto-loads. Written only
        // when the strategy defines servers (never clobbers a hand-authored file
        // with an empty one).
        if let mcp = McpConfigGenerator.json(for: strategy.mcpServers) {
            let url = repoURL.appendingPathComponent(McpConfigGenerator.fileName)
            try mcp.write(to: url, atomically: true, encoding: .utf8)
            written.append(McpConfigGenerator.fileName)
        }

        return written
    }

    // MARK: - Paths

    private var claudeMdURL: URL {
        repoURL.appendingPathComponent(ClaudeMdGenerator.fileName)
    }
}
