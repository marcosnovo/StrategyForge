//
//  AgentRole.swift
//  StrategyForge
//
//  One role in a strategy. A role expands into one or more Claude Code subagent
//  files (`.claude/agents/<name>-N.md`) — except the orchestrator, whose model is
//  a launch setting and which never gets a frontmatter file.
//

import Foundation

/// The kind of role a subagent plays. Drives sensible defaults (e.g. read-only
/// tools for reviewers/advisors/researchers) and the badge shown in the UI.
enum RoleKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case orchestrator
    case worker
    case advisor
    case reviewer
    case planner
    case researcher
    case specialist

    var id: String { rawValue }

    /// Short label for the role badge.
    var displayName: String {
        switch self {
        case .orchestrator: return "Orchestrator"
        case .worker: return "Worker"
        case .advisor: return "Advisor"
        case .reviewer: return "Reviewer"
        case .planner: return "Planner"
        case .researcher: return "Researcher"
        case .specialist: return "Specialist"
        }
    }

    /// Roles that must not modify the repository default to read-only tools.
    var isReadOnlyByDefault: Bool {
        switch self {
        case .advisor, .reviewer, .researcher:
            return true
        case .orchestrator, .worker, .planner, .specialist:
            return false
        }
    }
}

/// A single configurable role within a `Strategy`.
struct AgentRole: Codable, Identifiable, Hashable {
    var id: UUID
    /// Slug used as the subagent name / filename. Must be unique within a strategy
    /// and contain no spaces (see `Strategy` validation).
    var name: String
    var role: RoleKind
    /// The model pinned in this subagent's frontmatter. Ignored for the
    /// orchestrator, whose model is a launch setting (see `isOrchestrator`).
    var model: ClaudeModel
    /// The body of the generated `.md` file — editable.
    var systemPrompt: String
    /// Frontmatter `description`. This is what makes Claude decide to delegate, so
    /// it should be specific and action-oriented.
    var description: String
    /// Tools granted to the subagent. Empty means "inherit all".
    var tools: [String]
    /// Number of instances to expand this role into. Always 1 for the orchestrator.
    var count: Int
    /// Whether this role is the single orchestrator (the main session).
    var isOrchestrator: Bool

    init(
        id: UUID = UUID(),
        name: String,
        role: RoleKind,
        model: ClaudeModel,
        systemPrompt: String,
        description: String,
        tools: [String] = [],
        count: Int = 1,
        isOrchestrator: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.model = model
        self.systemPrompt = systemPrompt
        self.description = description
        self.tools = tools
        self.count = count
        self.isOrchestrator = isOrchestrator
    }
}
