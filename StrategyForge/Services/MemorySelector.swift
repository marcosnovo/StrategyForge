//
//  MemorySelector.swift
//  StrategyForge
//
//  Pure, deterministic ranking of which learnings to inject into a given run's context.
//  No I/O, no Date() — ordering derives only from the learnings' stored fields, so it's
//  fully unit-testable.
//

import Foundation

/// What a future run is about, used to match relevant learnings.
struct MemoryContext {
    var repoPath: String?
    var language: String?
    var taskText: String?

    /// Lowercased tokens (repo name, language, task words) a learning's tags can match.
    var tokens: Set<String> {
        var t = Set<String>()
        if let repoPath, !repoPath.isEmpty {
            t.insert((repoPath as NSString).lastPathComponent.lowercased())
        }
        if let language, !language.isEmpty { t.insert(language.lowercased()) }
        if let taskText {
            for w in taskText.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            where w.count >= 3 { t.insert(String(w)) }
        }
        return t
    }
}

enum MemorySelector {

    /// The top `limit` learnings for a context: repo-scoped entries only apply to their
    /// repo; then rank pinned-first, then **team level before personal** (a shared
    /// convention outranks a preference), then by tag overlap, then recency, then
    /// usefulness.
    ///
    /// Team learnings are also never squeezed out by a small `limit`: `topN` returns the
    /// applicable team entries plus as many personal ones as still fit. Policy that
    /// silently vanishes when the base grows isn't policy.
    static func topN(_ all: [Learning], context: MemoryContext, limit: Int) -> [Learning] {
        guard limit > 0 else { return [] }
        let repoName = context.repoPath.map { ($0 as NSString).lastPathComponent }
        let ctxTokens = context.tokens

        let eligible = all.filter { l in
            guard let scope = l.repoScope, !scope.isEmpty else { return true }   // global
            // Repo-scoped: apply only when the context is that repo (by path or name).
            return scope == context.repoPath || (repoName != nil && (scope as NSString).lastPathComponent == repoName)
        }

        func overlap(_ l: Learning) -> Int { l.tags.reduce(0) { $0 + (ctxTokens.contains($1.lowercased()) ? 1 : 0) } }

        // Ranking WITHIN one level — unchanged from before the levels existed, so a base
        // of purely personal learnings orders exactly as it always did.
        func ranked(_ pool: [Learning]) -> [Learning] {
            pool.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }                 // pinned first
                let oa = overlap(a), ob = overlap(b)
                if oa != ob { return oa > ob }                              // more tag overlap
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt } // newer
                if a.timesApplied != b.timesApplied { return a.timesApplied > b.timesApplied }
                return a.id.uuidString < b.id.uuidString                    // stable tiebreak
            }
        }

        // Team learnings are policy, so the whole team level is ranked ahead of the
        // personal one: when `limit` bites, a preference is dropped before a convention.
        let team = ranked(eligible.filter { $0.scope == .team })
        let personal = ranked(eligible.filter { $0.scope != .team })
        return Array((team + personal).prefix(limit))
    }
}
