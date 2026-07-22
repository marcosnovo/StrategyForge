//
//  AgentRole.swift
//  StrategyForge
//
//  One role in a strategy. A role expands into one or more Claude Code subagent
//  files (`.claude/agents/<name>-N.md`) — except the orchestrator, whose model is
//  a launch setting and which never gets a frontmatter file.
//

import Foundation
import SwiftUI

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

    /// An SF Symbol representing the role kind, used on the visual team canvas.
    var icon: String {
        switch self {
        case .orchestrator: return "point.3.connected.trianglepath.dotted"
        case .worker: return "hammer.fill"
        case .advisor: return "lightbulb.fill"
        case .reviewer: return "checkmark.seal.fill"
        case .planner: return "list.bullet.clipboard.fill"
        case .researcher: return "magnifyingglass"
        case .specialist: return "star.fill"
        }
    }

    /// Accent color for the role kind (matches RoleBadge). Coral identity: the
    /// orchestrator is always coral (warm, central, leads the eye); the team falls
    /// in a cool spectrum so the director stands out in any topology.
    var tint: Color {
        switch self {
        case .orchestrator: return Theme.coral        // the hero — full-strength coral
        case .worker:       return Theme.teal         // reef-water secondary
        case .planner:      return Theme.teamBlue     // governed, muted team spectrum
        case .researcher:   return Theme.teamGreen
        case .advisor:      return Theme.teamViolet
        case .reviewer:     return Theme.teamAmber
        case .specialist:   return Theme.teamRose
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
    /// The Claude model pinned in this subagent's frontmatter (used when this role
    /// runs on Claude). Ignored for the orchestrator, whose model is a launch setting.
    var model: ClaudeModel
    /// Which AI back-end runs this role. Enables cross-provider "mixes" (e.g. a GPT
    /// orchestrator with Gemini workers and a Claude advisor). Execution of non-Claude
    /// roles is a later phase; the choice is stored and shown now.
    var provider: AIProvider
    /// The chosen model id within `provider` when `provider != .claude` (else nil,
    /// and `model` applies).
    var providerModelID: String?
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
    /// Persistent per-agent memory: when on, this role reads + appends a durable notes
    /// file (`.claude/memory/<slug>.md`) so it carries learnings ACROSS runs, not just
    /// within one (that's the per-loop STATE.md). The generated subagent `.md` gets the
    /// read-first / append-last instructions, and the memory file is created on write.
    var memoryEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        role: RoleKind,
        model: ClaudeModel,
        provider: AIProvider = .claude,
        providerModelID: String? = nil,
        systemPrompt: String,
        description: String,
        tools: [String] = [],
        count: Int = 1,
        isOrchestrator: Bool = false,
        memoryEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.model = model
        self.provider = provider
        self.providerModelID = providerModelID
        self.systemPrompt = systemPrompt
        self.description = description
        self.tools = tools
        self.count = count
        self.isOrchestrator = isOrchestrator
        self.memoryEnabled = memoryEnabled
    }

    // Tolerant decode: roles saved before multi-provider default to Claude.
    enum CodingKeys: String, CodingKey {
        case id, name, role, model, provider, providerModelID
        case systemPrompt, description, tools, count, isOrchestrator, memoryEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Enum rawValues a newer app version may have written (an unknown model
        // id, role kind or provider) must not throw: one unknown value would fail
        // the decode of the WHOLE persisted store and wipe the user's data on the
        // next save. Fall back to sensible defaults instead.
        let roleRaw = (try? c.decode(String.self, forKey: .role)) ?? ""
        role = RoleKind(rawValue: roleRaw) ?? .worker
        let modelRaw = (try? c.decode(String.self, forKey: .model)) ?? ""
        model = ClaudeModel(rawValue: modelRaw) ?? .sonnet5
        let providerRaw = ((try? c.decodeIfPresent(String.self, forKey: .provider)) ?? nil) ?? ""
        provider = AIProvider(rawValue: providerRaw) ?? .claude
        providerModelID = try c.decodeIfPresent(String.self, forKey: .providerModelID)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        description = try c.decode(String.self, forKey: .description)
        tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? []
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        isOrchestrator = try c.decodeIfPresent(Bool.self, forKey: .isOrchestrator) ?? false
        memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? false
    }

    /// The repo-relative path of this role's persistent memory file (per expanded
    /// instance, so `worker-2` keeps its own notes).
    func memoryPath(instanceName: String) -> String { ".claude/memory/\(instanceName).md" }

    /// The model name to display for this role, honoring the provider choice.
    var modelDisplayName: String {
        if provider == .claude { return model.displayName }
        if let id = providerModelID, let m = provider.models.first(where: { $0.id == id }) {
            return m.displayName
        }
        return provider.models.first?.displayName ?? provider.displayName
    }

    /// Localization key for the capability tier shown under the model.
    var tierNameKey: String {
        if provider == .claude { return model.tierNameKey }
        if let id = providerModelID, let m = provider.models.first(where: { $0.id == id }) {
            return m.tierKey
        }
        return provider.models.first?.tierKey ?? "model.tier.generalist"
    }
}
