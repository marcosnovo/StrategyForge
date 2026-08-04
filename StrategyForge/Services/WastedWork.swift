//
//  WastedWork.swift
//  StrategyForge
//
//  "Your two agents are not collaborating — the second is redoing the first's work."
//  (Hanako, 2026). Duplicated effort is invisible in the final answer and only shows in the
//  TRAJECTORY: the same tool called with the same target by more than one agent means the
//  team paid for that step twice. This pure detector walks the activity timeline and surfaces
//  those repeats so the UI can make the waste visible (and so a handoff can be made to carry
//  evidence, not a lossy summary).
//

import Foundation

/// One piece of work that was done more than once across the run.
struct DuplicatedWork: Identifiable, Equatable, Sendable {
    var id: String { title + "\u{1}" + detail }
    var title: String        // the tool ("Read", "Bash", "WebFetch", …)
    var detail: String       // what it acted on (file, command, url, query)
    var count: Int           // total times it happened
    var agents: [String]     // distinct agents that did it ("orchestrator" for the lead)
    /// Redone across DIFFERENT agents (the collaboration failure), vs one agent looping.
    var crossAgent: Bool { agents.count > 1 }
}

enum WastedWork {
    /// Timeline markers that aren't real tool work (delegations, role heartbeats) — excluded.
    private static func isToolStep(_ s: ActivityStep) -> Bool {
        guard !s.isDelegation else { return false }
        if s.title.hasPrefix("role.") { return false }
        // Needs a concrete target to be a meaningful "same work" key (a bare tool name with no
        // target — e.g. "TodoWrite" — isn't duplicated *work* in a comparable sense).
        return !(s.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func agentLabel(_ s: ActivityStep) -> String {
        (s.agent?.isEmpty ?? true) ? "orchestrator" : s.agent!
    }

    /// Find tool steps repeated (same tool + same target) across the timeline. Sorted by the
    /// most-repeated first; ties broken by cross-agent (the worse kind) then title.
    static func detect(_ steps: [ActivityStep]) -> [DuplicatedWork] {
        var order: [String] = []
        var byKey: [String: (title: String, detail: String, count: Int, agents: [String])] = [:]
        for s in steps where isToolStep(s) {
            let detail = s.detail!.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = s.title + "\u{1}" + detail
            if byKey[key] == nil { byKey[key] = (s.title, detail, 0, []); order.append(key) }
            byKey[key]!.count += 1
            let a = agentLabel(s)
            if !byKey[key]!.agents.contains(a) { byKey[key]!.agents.append(a) }
        }
        return order.compactMap { key -> DuplicatedWork? in
            guard let v = byKey[key], v.count > 1 else { return nil }
            return DuplicatedWork(title: v.title, detail: v.detail, count: v.count, agents: v.agents)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.crossAgent != $1.crossAgent { return $0.crossAgent }
            return $0.title < $1.title
        }
    }

    /// Total number of REDUNDANT tool calls (occurrences beyond the first of each duplicated
    /// step) — the count of work the team paid for more than once.
    static func redundantCount(_ dups: [DuplicatedWork]) -> Int {
        dups.reduce(0) { $0 + ($1.count - 1) }
    }
}
