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
//  GRANULARITY: attribution is now per-LINE on the native run. Each `fileEdited` event
//  is paired with the active subagent AND a snapshot diff of the file, so the lines a
//  given edit changed are credited to whoever was active for that edit (see
//  `LineAttributor`). The changed-files row still shows a file-level dot (the last
//  editor); the diff shows per-line authorship. Cross-provider line attribution is a
//  separate future step — the workers on that path return text today, they don't edit
//  files in the repo — so per-line provenance is Claude-native for now.
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

/// Per-line authorship via a snapshot diff: given a file's previous lines (with their
/// authors) and its new lines after an edit, credit the lines this edit changed to
/// `author` while carrying unchanged lines' authorship forward. Pure LCS alignment, so
/// it's unit-tested directly. The first time a file is seen there's no prior snapshot, so
/// every line is credited to the first editor; later edits refine it line by line.
enum LineAttributor {

    /// A quadratic-LCS guard: past this many line-pairs we skip alignment and credit the
    /// whole new file to `author` (coarse but bounded — huge generated files won't stall
    /// the run). ~2M pairs ≈ a 1.4k×1.4k line diff.
    static let maxPairs = 2_000_000

    static func attribute(old: [String], oldAuthors: [EditProvenance?],
                          new: [String], author: EditProvenance) -> [EditProvenance?] {
        let n = old.count, m = new.count
        guard m > 0 else { return [] }
        // No prior version, or a diff too large to align: credit everything to this edit.
        guard n > 0, n * m <= maxPairs else { return Array(repeating: author, count: m) }

        // dp[i][j] = LCS length of old[i...] and new[j...].
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = old[i] == new[j] ? dp[i + 1][j + 1] + 1
                                            : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        // Backtrack: matched lines keep their prior author; inserted lines get `author`.
        var result = [EditProvenance?](repeating: author, count: m)
        var i = 0, j = 0
        while i < n && j < m {
            if old[i] == new[j] {
                result[j] = i < oldAuthors.count ? oldAuthors[i] : nil
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1                          // line removed from old
            } else {
                result[j] = author; j += 1      // line inserted in new
            }
        }
        // Any remaining new lines (j..<m) are trailing inserts — already `author`.
        return result
    }
}
