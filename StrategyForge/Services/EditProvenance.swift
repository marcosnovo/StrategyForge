//
//  EditProvenance.swift
//  StrategyForge
//
//  Who wrote this change — per-file authorship for Code mode's diff. Coral's whole
//  point is putting different models/providers on different roles in one team; this
//  surfaces the payoff in the diff itself: each changed file is tagged with the agent
//  (and its pinned model/provider) that last edited it, so a mixed-provider run is
//  auditable at a glance instead of an anonymous pile of edits.
//
//  GRANULARITY / HONESTY: attribution is at the FILE level, taken from the CLI's
//  `fileEdited` events paired with the active subagent — the resolution the native run
//  actually exposes reliably. True per-LINE, cross-provider attribution needs each
//  worker to edit in an isolated worktree we diff against (the workers on the
//  cross-provider path return text today, they don't touch files), so that's a larger
//  change; this is the reliable first step, and the model is line-capable for later.
//

import Foundation

/// The team member credited with a file's changes.
struct EditProvenance: Equatable, Hashable, Sendable {
    /// The subagent/role name, or nil when the orchestrator itself made the edit.
    var agent: String?
    /// A friendly model label (e.g. "Sonnet 5"); empty when unknown.
    var model: String
    /// The provider that ran the edit — drives the badge tint/icon.
    var provider: AIProvider

    /// Compact "Agent · Model" for the badge; falls back to the orchestrator's name when
    /// there's no subagent, and drops the model when it's unknown.
    func label(orchestratorName: String) -> String {
        let who = (agent?.isEmpty == false ? agent : nil) ?? orchestratorName
        return model.isEmpty ? who : "\(who) · \(model)"
    }
}

/// Resolves an edit (an active-subagent name at edit time) to the responsible team member
/// by matching it against the strategy's roles — pure, so it's unit-tested directly.
enum EditProvenanceResolver {

    /// Attribute an edit made while `subagent` was active to a concrete team member.
    /// - No active subagent → the orchestrator (with its configured model/provider).
    /// - A subagent that matches a role → that role's pinned model/provider.
    /// - A subagent with no matching role → credited by name, model unknown (best-effort).
    static func attribute(subagent: String?, strategy: Strategy) -> EditProvenance {
        let sub = subagent?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sub, !sub.isEmpty else {
            if let orch = strategy.orchestrator {
                return EditProvenance(agent: nil, model: orch.modelDisplayName, provider: orch.provider)
            }
            return EditProvenance(agent: nil, model: "", provider: .claude)
        }
        let match = strategy.subagentRoles.first { AgentNameMatcher.titlesMatch($0.name, sub) }
            ?? strategy.subagentRoles.first { $0.name.caseInsensitiveCompare(sub) == .orderedSame }
        if let role = match {
            return EditProvenance(agent: role.name, model: role.modelDisplayName, provider: role.provider)
        }
        return EditProvenance(agent: sub, model: "", provider: .claude)
    }
}
