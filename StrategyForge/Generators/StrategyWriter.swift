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
//   • Deletes ONLY agent/workflow files it previously generated (managed-signature)
//     that are no longer part of the strategy; hand-written files are never touched.
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
        // Per-agent memory seeds are created ONCE and then owned by the agent, so only
        // show (and later write) the ones that don't exist yet — an existing memory file
        // is never overwritten, and the preview must reflect exactly that.
        for seed in AgentFileGenerator.memorySeedFiles(for: strategy)
        where !fm.fileExists(atPath: repoURL.appendingPathComponent(seed.relativePath).path) {
            files.append(seed)
        }
        // A team (with teammates) also gets a runnable dynamic workflow — the team's
        // topology as a program Claude Code can execute (plan → parallel work → synthesize).
        if let workflow = WorkflowGenerator.workflow(for: strategy) {
            files.append(GeneratedFile(relativePath: WorkflowGenerator.fileName(for: strategy), contents: workflow))
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
        // Same for generated workflows: renaming the team (or editing it down to
        // solo) would otherwise leave a stale runnable .mjs behind.
        for rel in prunedWorkflowPaths(for: strategy) {
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

    /// Managed workflow files we previously generated that no longer match the
    /// team: the slug changed (rename) or the team no longer yields a workflow
    /// at all (edited down to solo / no valid roles). `write()` deletes exactly
    /// these; the preview uses the same list so the two never diverge. Only
    /// files bearing the generated-workflow signature qualify — hand-written
    /// workflows are never touched.
    func prunedWorkflowPaths(for strategy: Strategy) -> [String] {
        let workflowsDir = repoURL.appendingPathComponent(WorkflowGenerator.workflowsDirectory,
                                                          isDirectory: true)
        let expected: Set<String> = WorkflowGenerator.workflow(for: strategy) == nil
            ? [] : [WorkflowGenerator.fileName(for: strategy)]
        guard let entries = try? fm.contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var pruned: [String] = []
        for entry in entries where entry.pathExtension == "mjs" {
            let rel = "\(WorkflowGenerator.workflowsDirectory)/\(entry.lastPathComponent)"
            guard !expected.contains(rel),
                  let content = try? String(contentsOf: entry, encoding: .utf8),
                  content.contains(WorkflowGenerator.managedSignature) else { continue }
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

        // 2a. Per-agent memory seeds — create ONLY if absent so the agent's accumulated
        // notes are never clobbered by a re-generate (same create-once rule as skills).
        for seed in AgentFileGenerator.memorySeedFiles(for: strategy) {
            let url = repoURL.appendingPathComponent(seed.relativePath)
            if fm.fileExists(atPath: url.path) { continue }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try seed.contents.write(to: url, atomically: true, encoding: .utf8)
            written.append(seed.relativePath)
        }

        // 2a-bis. Dynamic workflow — the team's topology as a runnable Claude Code program.
        // Regenerated like the agent files (reflects the current team), so it's overwritten.
        // Prune stale generated workflows first (renamed team / solo downgrade), using
        // the SAME list the preview diff surfaces (prunedWorkflowPaths).
        for rel in prunedWorkflowPaths(for: strategy) {
            try? fm.removeItem(at: repoURL.appendingPathComponent(rel))
        }
        if let workflow = WorkflowGenerator.workflow(for: strategy) {
            let url = repoURL.appendingPathComponent(WorkflowGenerator.fileName(for: strategy))
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try workflow.write(to: url, atomically: true, encoding: .utf8)
            written.append(WorkflowGenerator.fileName(for: strategy))
        }

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

        // 3. .mcp.json — external tool servers Claude Code auto-loads. MERGE into any
        // existing file so a hand-authored server list is preserved (ours win only on a
        // name collision); an unparseable existing file is left untouched.
        let mcpURL = repoURL.appendingPathComponent(McpConfigGenerator.fileName)
        let existingMcp = try? String(contentsOf: mcpURL, encoding: .utf8)
        if let mcp = McpConfigGenerator.mergedJSON(existing: existingMcp, for: strategy.mcpServers) {
            try mcp.write(to: mcpURL, atomically: true, encoding: .utf8)
            written.append(McpConfigGenerator.fileName)
        }

        return written
    }

    // MARK: - Paths

    private var claudeMdURL: URL {
        repoURL.appendingPathComponent(ClaudeMdGenerator.fileName)
    }
}
