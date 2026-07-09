//
//  ClaudeConfigParser.swift
//  StrategyForge
//
//  The inverse of AgentFileGenerator + ClaudeMdGenerator: read an existing repo's
//  .claude/agents/*.md and CLAUDE.md back into an editable Strategy. Tolerant of
//  hand-written files (not just StrategyForge output). Pure — no disk access; the
//  caller passes file contents.
//
//  Recovery rules (faithful to how the app writes):
//   • Each agent file → a subagent role (name/description/tools/model from
//     frontmatter, systemPrompt from the body).
//   • `<base>-1.md … <base>-N.md` with matching model/tools collapse into one role
//     with count = N (mirror of AgentFileGenerator's count expansion).
//   • The orchestrator has no file; it is recovered from the CLAUDE.md managed
//     block (name + suggested model), or synthesized if absent.
//   • Role kinds come from the CLAUDE.md subagent table when present, else a name
//     heuristic (review/advisor/research/plan/special → matching kind, else worker).
//

import Foundation

enum ClaudeConfigParser {

    /// A single agent file's raw input.
    struct AgentFile { let fileName: String; let contents: String }

    /// An intermediate parsed agent record.
    private struct Parsed { let name: String; let model: ClaudeModel; let tools: [String]; let description: String; let body: String }

    /// Parse a repo's Claude Code config into a Strategy.
    static func parse(agentFiles: [AgentFile], claudeMd: String?, fallbackName: String) -> Strategy {
        let meta = claudeMd.map(parseClaudeMd) ?? ClaudeMdMeta()

        // Parse every agent file into an intermediate record.
        var parsed: [Parsed] = []
        for file in agentFiles {
            guard let fm = parseFrontmatter(file.contents) else { continue }
            let name = fm.fields["name"] ?? file.fileName.replacingOccurrences(of: ".md", with: "")
            let model = fm.fields["model"].flatMap(ClaudeModel.init(rawValue:)) ?? .sonnet5
            let tools = (fm.fields["tools"]).map(splitTools) ?? []
            parsed.append(Parsed(name: name, model: model, tools: tools,
                                 description: fm.fields["description"] ?? "", body: fm.body))
        }

        // Collapse `<base>-N` groups (≥2 numbered instances) into a single role.
        var subagentRoles: [AgentRole] = []
        var handledIndices = Set<Int>()
        for (i, p) in parsed.enumerated() {
            if handledIndices.contains(i) { continue }
            let (base, hadSuffix) = splitNumericSuffix(p.name)
            if hadSuffix {
                // Gather siblings sharing the base with a numeric suffix.
                let siblings = parsed.enumerated().filter { (_, q) in
                    let (b, s) = splitNumericSuffix(q.name)
                    return s && b == base
                }
                if siblings.count >= 2 {
                    siblings.forEach { handledIndices.insert($0.offset) }
                    subagentRoles.append(makeRole(name: base, from: p, count: siblings.count, meta: meta))
                    continue
                }
            }
            handledIndices.insert(i)
            subagentRoles.append(makeRole(name: p.name, from: p, count: 1, meta: meta))
        }

        // Orchestrator (no file) — from CLAUDE.md, or a sensible default.
        let orchestrator = AgentRole(
            name: meta.orchestratorName ?? "orchestrator",
            role: .orchestrator,
            model: meta.orchestratorModel ?? .fable5,
            systemPrompt: meta.orchestrationNotes ?? "You are the orchestrator (the main session). Plan, delegate to the subagents below, and integrate their results.",
            description: "The main session that coordinates the team.",
            tools: [],
            count: 1,
            isOrchestrator: true
        )

        return Strategy(
            name: meta.strategyName ?? fallbackName,
            description: meta.strategyDescription ?? "Imported from an existing .claude/ configuration.",
            roles: [orchestrator] + subagentRoles,
            orchestrationNotes: meta.orchestrationNotes ?? "The orchestrator delegates to the subagents below and integrates their results. Single level of delegation; subagents report back and never talk to each other."
        )
    }

    private static func makeRole(name: String, from p: Parsed, count: Int, meta: ClaudeMdMeta) -> AgentRole {
        let kind = meta.roleKinds[name] ?? inferKind(name: name)
        return AgentRole(
            name: name,
            role: kind,
            model: p.model,
            systemPrompt: p.body,
            description: p.description,
            tools: p.tools,
            count: count,
            isOrchestrator: false
        )
    }

    // MARK: - Frontmatter

    struct Frontmatter { let fields: [String: String]; let body: String }

    /// Parse a `---`-fenced YAML-ish frontmatter block plus the body after it.
    static func parseFrontmatter(_ text: String) -> Frontmatter? {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var fields: [String: String] = [:]
        var i = 1
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces) != "---" {
            let line = lines[i]
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let raw = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { fields[key] = unquote(raw) }
            }
            i += 1
        }
        guard i < lines.count else { return nil } // no closing fence
        let body = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Frontmatter(fields: fields, body: body)
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func splitTools(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Returns the base name and whether a trailing `-<digits>` suffix was stripped.
    private static func splitNumericSuffix(_ name: String) -> (base: String, hadSuffix: Bool) {
        guard let dash = name.lastIndex(of: "-") else { return (name, false) }
        let suffix = name[name.index(after: dash)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return (name, false) }
        return (String(name[..<dash]), true)
    }

    private static func inferKind(name: String) -> RoleKind {
        let n = name.lowercased()
        if n.contains("review") { return .reviewer }
        if n.contains("advis") { return .advisor }
        if n.contains("research") { return .researcher }
        if n.contains("plan") { return .planner }
        if n.contains("special") { return .specialist }
        return .worker
    }

    // MARK: - CLAUDE.md managed block

    struct ClaudeMdMeta {
        var strategyName: String?
        var strategyDescription: String?
        var orchestratorName: String?
        var orchestratorModel: ClaudeModel?
        var orchestrationNotes: String?
        var roleKinds: [String: RoleKind] = [:]
    }

    /// Best-effort recovery of metadata from the StrategyForge-managed block.
    static func parseClaudeMd(_ text: String) -> ClaudeMdMeta {
        var meta = ClaudeMdMeta()
        // Restrict to the managed block if present.
        let scope: String
        if let s = text.range(of: ClaudeMdGenerator.startMarker),
           let e = text.range(of: ClaudeMdGenerator.endMarker) {
            scope = String(text[s.upperBound..<e.lowerBound])
        } else {
            scope = text
        }

        meta.strategyName = firstMatch(in: scope, prefix: "# Multi-agent strategy:")
        meta.orchestratorName = between(scope, "main Claude Code session** (`", "`)")
        if let idPart = between(scope, "Suggested model: **", ")"),
           let idOpen = idPart.range(of: "(`") {
            let id = String(idPart[idOpen.upperBound...]).replacingOccurrences(of: "`", with: "")
            meta.orchestratorModel = ClaudeModel(rawValue: id.trimmingCharacters(in: .whitespaces))
        }
        meta.orchestrationNotes = section(scope, header: "## How to orchestrate")
        // Description = the paragraph right after the title line.
        if let name = meta.strategyName,
           let titleRange = scope.range(of: "# Multi-agent strategy: \(name)") {
            let after = scope[titleRange.upperBound...]
            let paras = after.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            meta.strategyDescription = paras.first(where: { !$0.isEmpty && !$0.hasPrefix(">") && !$0.hasPrefix("#") })
        }
        meta.roleKinds = parseRoleTable(scope)
        return meta
    }

    /// Parse the "| `name` | Role | Model | ... |" subagent table into name→kind.
    private static func parseRoleTable(_ text: String) -> [String: RoleKind] {
        var map: [String: RoleKind] = [:]
        let byDisplayName: [String: RoleKind] = Dictionary(
            uniqueKeysWithValues: RoleKind.allCases.map { ($0.displayName, $0) })
        for line in text.components(separatedBy: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2 else { continue }
            // First cell: `name` or `name-1`…`name-N`; take the first backticked token, strip suffix.
            let nameCell = cells[0]
            guard let open = nameCell.firstIndex(of: "`") else { continue }
            let afterOpen = nameCell[nameCell.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "`") else { continue }
            var name = String(afterOpen[..<close])
            if let dash = name.lastIndex(of: "-"), name[name.index(after: dash)...].allSatisfy(\.isNumber) {
                name = String(name[..<dash])
            }
            if let kind = byDisplayName[cells[1]] { map[name] = kind }
        }
        return map
    }

    // MARK: - Small text helpers

    private static func firstMatch(in text: String, prefix: String) -> String? {
        for line in text.components(separatedBy: "\n") where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func between(_ text: String, _ start: String, _ end: String) -> String? {
        guard let s = text.range(of: start) else { return nil }
        let rest = text[s.upperBound...]
        guard let e = rest.range(of: end) else { return nil }
        return String(rest[..<e.lowerBound])
    }

    private static func section(_ text: String, header: String) -> String? {
        guard let h = text.range(of: header) else { return nil }
        let after = text[h.upperBound...]
        let body: Substring
        if let next = after.range(of: "\n## ") {
            body = after[..<next.lowerBound]
        } else {
            body = after
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
