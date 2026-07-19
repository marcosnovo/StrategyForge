//
//  AgentFileGenerator.swift
//  StrategyForge
//
//  Pure, testable generation of Claude Code subagent files
//  (`.claude/agents/<name>.md`) from a Strategy. No disk access.
//

import Foundation

/// Turns a `Strategy` into subagent markdown files. The orchestrator is skipped
/// entirely — its model is a launch setting, so it never gets a frontmatter file.
enum AgentFileGenerator {

    /// Directory (relative to repo root) where subagent files live.
    static let agentsDirectory = ".claude/agents"

    /// Frontmatter marker identifying an agent file StrategyForge generated, so a
    /// re-write can safely prune the ones it wrote for now-removed/renamed roles
    /// WITHOUT ever touching hand-written agent files. (Ignored by Claude Code and
    /// by our own parser, which only reads name/model/tools/description.)
    static let managedSignature = "coral: managed"
    /// Legacy signature from the app's former name — still recognized when pruning
    /// so agent files written by an earlier version are managed, not orphaned.
    static let legacyManagedSignature = "strategyforge: managed"

    /// Generate one `GeneratedFile` per subagent instance, expanding `count`.
    ///
    /// A role with `count == 1` produces `<name>.md`; a role with `count > 1`
    /// produces `<name>-1.md … <name>-N.md`, and each file's `name` frontmatter is
    /// suffixed to match (subagent names must be unique).
    static func generate(for strategy: Strategy) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        for role in strategy.subagentRoles {
            // Defense in depth: the editor blocks invalid names via validate(),
            // but strategies also arrive from imports and sync. A name with "/",
            // ".." or newlines would escape .claude/agents/ or inject frontmatter
            // — never build a path from it.
            guard Strategy.isValidRoleName(role.name) else { continue }
            let count = max(role.count, 1)
            for index in 1...count {
                let instanceName = count == 1 ? role.name : "\(role.name)-\(index)"
                let contents = markdown(for: role, instanceName: instanceName)
                files.append(GeneratedFile(
                    relativePath: "\(agentsDirectory)/\(instanceName).md",
                    contents: contents
                ))
            }
        }
        return files
    }

    /// Render a single subagent file's contents.
    static func markdown(for role: AgentRole, instanceName: String) -> String {
        var frontmatter = "---\n"
        frontmatter += "name: \(instanceName)\n"
        frontmatter += "description: \(escapedScalar(role.description))\n"
        // Omit `tools` entirely when empty so the subagent inherits all tools.
        // Strip newlines from each entry: a tool name with "\n" (or a raw "\r" —
        // YAML treats CR as a line break too) would break out of the scalar and
        // inject its own frontmatter lines.
        let tools = role.tools
            .map {
                $0.replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        if !tools.isEmpty {
            frontmatter += "tools: \(tools.joined(separator: ", "))\n"
        }
        // Workers pin their model in frontmatter (unlike the orchestrator).
        frontmatter += "model: \(role.model.rawValue)\n"
        frontmatter += "\(managedSignature)\n"
        frontmatter += "---\n"

        var body = role.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // Persistent per-agent memory: instruct this instance to read its notes first
        // and append durable learnings last, so run N+1 builds on run N (unlike the
        // per-loop STATE.md, this is scoped to THIS agent and survives across teams/runs).
        if role.memoryEnabled {
            body += "\n\n" + memoryInstructions(memoryPath: role.memoryPath(instanceName: instanceName))
        }
        return frontmatter + "\n" + body + "\n"
    }

    /// The "## Memory" block appended to a memory-enabled subagent's instructions.
    static func memoryInstructions(memoryPath: String) -> String {
        """
        ## Memory

        You keep a persistent memory file at `\(memoryPath)`. At the START of every task,
        read it to recall what earlier runs learned. At the END, append any DURABLE
        learnings — decisions made, conventions in this codebase, dead ends to avoid — in
        a concise line or two. Don't repeat what's already there, and prune anything now
        wrong. This file carries across runs, so keep it short and high-signal.
        """
    }

    /// Seed memory files for roles with persistent memory ON. These are written ONCE and
    /// then owned by the agent (StrategyWriter never overwrites an existing one), so the
    /// accumulated notes are never clobbered by a re-generate. One per expanded instance.
    static func memorySeedFiles(for strategy: Strategy) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        for role in strategy.subagentRoles where role.memoryEnabled {
            guard Strategy.isValidRoleName(role.name) else { continue }
            let count = max(role.count, 1)
            for index in 1...count {
                let instanceName = count == 1 ? role.name : "\(role.name)-\(index)"
                files.append(GeneratedFile(
                    relativePath: role.memoryPath(instanceName: instanceName),
                    contents: memorySeed(instanceName: instanceName)))
            }
        }
        return files
    }

    private static func memorySeed(instanceName: String) -> String {
        """
        # Memory — \(instanceName)

        Durable notes this agent keeps across runs. It reads this first and appends
        concise, lasting learnings last (decisions, conventions found, dead ends). Keep it
        short and high-signal; prune anything stale.
        """
    }

    /// YAML-safe rendering of a single-line scalar. `description` can contain colons
    /// and other YAML-significant characters, so quote it when needed.
    private static func escapedScalar(_ value: String) -> String {
        // \r\n and bare \r count as line breaks in YAML — flatten them all, or an
        // imported description with raw CRs injects its own frontmatter lines.
        let flat = value.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        // YAML-reserved leading characters (alias/anchor/tag/directive/etc.) force quoting.
        let reservedPrefixes = ["'", "\"", ">", "|", "-", "[", "{",
                                "*", "&", "!", "%", "@", "`", "?", "~"]
        let needsQuoting = flat.contains(":") || flat.contains("#")
            || reservedPrefixes.contains(where: { flat.hasPrefix($0) })
        guard needsQuoting else { return flat }
        // Double-quote and escape embedded double quotes/backslashes.
        let escaped = flat
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
