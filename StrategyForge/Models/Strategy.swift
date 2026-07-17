//
//  Strategy.swift
//  StrategyForge
//
//  A strategy is a topology: a named set of roles plus honest orchestration notes
//  describing how the (single) orchestrator delegates and what the limitations are.
//

import Foundation

/// A multi-agent topology, fully editable (model and count per role).
struct Strategy: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var roles: [AgentRole]
    /// Prose that goes into `CLAUDE.md` explaining how the orchestrator should
    /// delegate and the limitations (single level of delegation, no lateral
    /// worker-to-worker communication). Must be honest about the Claude Code model.
    var orchestrationNotes: String
    /// External tool servers (MCP) this strategy makes available — written to
    /// `.mcp.json` in the project so Claude Code auto-loads them.
    var mcpServers: [McpServer]
    /// Attached skill slugs (folders under ~/.claude/skills or the repo's
    /// .claude/skills). On generate, StrategyWriter copies them into the project's
    /// .claude/skills and CLAUDE.md lists them so agents know they're available.
    var skills: [String]

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        roles: [AgentRole],
        orchestrationNotes: String,
        mcpServers: [McpServer] = [],
        skills: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.roles = roles
        self.orchestrationNotes = orchestrationNotes
        self.mcpServers = mcpServers
        self.skills = skills
    }

    // Tolerant decode: `mcpServers`/`skills` are new, so strategies saved by older
    // versions (Configuration/SavedTeam JSON) simply default to none. Encode stays synthesized.
    enum CodingKeys: String, CodingKey {
        case id, name, description, roles, orchestrationNotes, mcpServers, skills
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        roles = try c.decode([AgentRole].self, forKey: .roles)
        orchestrationNotes = try c.decode(String.self, forKey: .orchestrationNotes)
        mcpServers = try c.decodeIfPresent([McpServer].self, forKey: .mcpServers) ?? []
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
    }

    // MARK: - Convenience

    /// The single orchestrator role, if the strategy is well-formed.
    var orchestrator: AgentRole? {
        roles.first { $0.isOrchestrator }
    }

    /// All non-orchestrator roles — the ones that become subagent files.
    var subagentRoles: [AgentRole] {
        roles.filter { !$0.isOrchestrator }
    }
}

// MARK: - MCP

/// One MCP (Model Context Protocol) tool server the project exposes to the agents.
/// Serialized into `.mcp.json` as `{ name: { command, args, env } }`, which Claude
/// Code auto-loads from the project root.
struct McpServer: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String                 // the server key, e.g. "github"
    var command: String              // launcher, e.g. "npx" or an absolute path
    var args: [String]
    var env: [String: String]

    init(id: UUID = UUID(), name: String = "", command: String = "",
         args: [String] = [], env: [String: String] = [:]) {
        self.id = id; self.name = name; self.command = command; self.args = args; self.env = env
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }
}

// MARK: - Validation

extension Strategy {

    /// A single validation problem, surfaced inline in the editor.
    struct ValidationIssue: Identifiable, Hashable {
        enum Severity: Hashable { case error, warning }
        let id = UUID()
        let severity: Severity
        let message: String
        /// The role this issue relates to, if any (for row-level highlighting).
        let roleID: UUID?

        init(severity: Severity, message: String, roleID: UUID? = nil) {
            self.severity = severity
            self.message = message
            self.roleID = roleID
        }
    }

    /// All validation issues for the current state. Empty `errors` means the
    /// strategy can be generated safely.
    func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Exactly one orchestrator.
        let orchestrators = roles.filter { $0.isOrchestrator }
        switch orchestrators.count {
        case 0:
            issues.append(.init(severity: .error,
                message: "A strategy must have exactly one orchestrator; none is marked."))
        case 1:
            break
        default:
            issues.append(.init(severity: .error,
                message: "A strategy must have exactly one orchestrator; \(orchestrators.count) are marked."))
        }

        // Orchestrator constraints: count is always 1 and its model is a launch
        // setting (documented in CLAUDE.md), never frontmatter — so we warn if a
        // count other than 1 slipped in.
        for orch in orchestrators where orch.count != 1 {
            issues.append(.init(severity: .error,
                message: "The orchestrator must have a count of 1.",
                roleID: orch.id))
        }

        // Unique, non-empty slug names. Names become file paths under
        // .claude/agents/ and YAML `name:` scalars, so anything beyond
        // [A-Za-z0-9_-] (slashes, "..", newlines, colons…) must be blocked —
        // an imported strategy could otherwise write outside the repo or
        // inject frontmatter.
        var seen: [String: Int] = [:]
        for role in roles {
            let trimmed = role.name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                issues.append(.init(severity: .error,
                    message: "A role has an empty name.", roleID: role.id))
            } else if !Strategy.isValidRoleName(role.name) {
                issues.append(.init(severity: .error,
                    message: "Role name “\(role.name)” is invalid; use only letters, digits, “-” or “_” (e.g. “code-reviewer”).",
                    roleID: role.id))
            }
            seen[role.name, default: 0] += 1
        }
        for (name, freq) in seen where freq > 1 {
            issues.append(.init(severity: .error,
                message: "Duplicate role name “\(name)”. Subagent names must be unique."))
        }

        // Expanded-name collisions: a role "worker" with count 3 writes worker-1…worker-3,
        // and a SEPARATE literal role "worker-1" writes the SAME file — different role
        // names, same generated `.md`, so one agent is silently lost. Mirror the file
        // expansion (name-N for count>1, name for count 1) and flag any clash.
        var expanded: [String: Int] = [:]
        for role in roles where !role.isOrchestrator {
            let count = max(role.count, 1)
            if count == 1 { expanded[role.name, default: 0] += 1 }
            else { for i in 1...count { expanded["\(role.name)-\(i)", default: 0] += 1 } }
        }
        for (name, freq) in expanded where freq > 1 {
            issues.append(.init(severity: .error,
                message: "Two subagents both generate “\(name).md” — a numbered role collides with another name. Rename one."))
        }

        // Counts must be positive.
        for role in roles where role.count < 1 {
            issues.append(.init(severity: .error,
                message: "Role “\(role.name)” has a count below 1.", roleID: role.id))
        }

        // Unknown tool names (typically from an import): warn, since Claude Code silently
        // ignores tools it doesn't recognize. Scoped patterns — Bash(…), a permission
        // pattern, or an mcp__ server tool — are legitimate and not flagged.
        let known = Set(Constants.availableTools)
        for role in roles {
            let unknown = role.tools.filter { t in
                let name = t.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return false }
                return !known.contains(name) && !name.contains("(") && !name.hasPrefix("mcp__")
            }
            if !unknown.isEmpty {
                issues.append(.init(severity: .warning,
                    message: "“\(role.name)” lists unrecognized tool(s): \(unknown.joined(separator: ", ")). Claude Code may ignore them.",
                    roleID: role.id))
            }
        }

        // Reviewers/advisors/researchers should not hold write tools.
        let writeTools: Set<String> = ["Write", "Edit", "Bash"]
        for role in roles where role.role.isReadOnlyByDefault && !role.isOrchestrator {
            let granted = Set(role.tools)
            let offending = granted.intersection(writeTools)
            if !offending.isEmpty {
                issues.append(.init(severity: .warning,
                    message: "“\(role.name)” is a \(role.role.displayName.lowercased()) but can \(offending.sorted().joined(separator: ", ")). Consider read-only tools.",
                    roleID: role.id))
            }
        }

        // Workers should not hold the delegation tool — Claude Code allows only a
        // single level of delegation.
        for role in subagentRoles where role.tools.contains("Agent") {
            issues.append(.init(severity: .warning,
                message: "“\(role.name)” is granted the Agent tool, but subagents cannot delegate further (single level of delegation).",
                roleID: role.id))
        }

        return issues
    }

    /// Only the blocking issues.
    var errors: [ValidationIssue] {
        validate().filter { $0.severity == .error }
    }

    /// True when there are no blocking errors.
    var isValid: Bool { errors.isEmpty }

    /// Safe slug for a subagent name: it is used verbatim as a file name and as a
    /// YAML scalar, so restrict it to ASCII letters, digits, "-" and "_".
    static func isValidRoleName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    // MARK: - Auto-fix

    /// True when at least one issue can be resolved automatically.
    var hasAutoFixableIssues: Bool { self != autoFixed() }

    /// Return a copy with all safe, mechanical issues fixed:
    ///  • read-only roles (advisor/reviewer/researcher) lose write tools;
    ///  • subagents lose the `Agent` tool (single level of delegation);
    ///  • counts below 1 are clamped to 1;
    ///  • duplicate role names get a numeric suffix.
    /// Structural problems (e.g. missing orchestrator) are left for the user.
    func autoFixed() -> Strategy {
        var copy = self
        let writeTools: Set<String> = ["Write", "Edit", "Bash"]

        for i in copy.roles.indices {
            if copy.roles[i].role.isReadOnlyByDefault && !copy.roles[i].isOrchestrator {
                copy.roles[i].tools.removeAll { writeTools.contains($0) }
            }
            if !copy.roles[i].isOrchestrator {
                copy.roles[i].tools.removeAll { $0 == "Agent" }
            }
            if copy.roles[i].count < 1 { copy.roles[i].count = 1 }
            if copy.roles[i].isOrchestrator { copy.roles[i].count = 1 }
        }

        // De-duplicate names deterministically (append -2, -3, … to later dupes).
        var seen: [String: Int] = [:]
        for i in copy.roles.indices {
            let name = copy.roles[i].name
            if let n = seen[name] {
                let next = n + 1
                seen[name] = next
                copy.roles[i].name = "\(name)-\(next)"
            } else {
                seen[name] = 1
            }
        }
        return copy
    }
}
