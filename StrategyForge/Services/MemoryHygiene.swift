//
//  MemoryHygiene.swift
//  StrategyForge
//
//  The "forgetting" half of a memory system (Stanford/Microsoft/Anthropic framing: a memory
//  engineer optimizes what to LET GO, not just what to keep). Coral already does the remembering
//  half well — distilled facts/skills, density-ranked, review-gated injection. This adds the two
//  things it lacked:
//
//   • Staleness — a learning nobody has used in a long time (and that's old) is a candidate to
//     forget. We never delete automatically; we SURFACE it for the human to keep or drop.
//   • Contradictions — two learnings giving conflicting guidance on the same subject. We never
//     auto-merge them ("both may have been right in different contexts"); we surface, you decide.
//
//  Pure and deterministic (time is injected), so it's unit-tested and cheap to recompute.
//

import Foundation

enum MemoryStaleness: String, Sendable {
    case fresh      // recently created or applied
    case aging      // getting old / unused — worth a glance
    case stale      // old AND long unused — a candidate to forget

    var labelKey: String { "memory.staleness.\(rawValue)" }
}

/// Two learnings that give conflicting guidance about the same subject + scope.
struct MemoryConflict: Identifiable, Equatable, Sendable {
    var id: String { [a.uuidString, b.uuidString].sorted().joined(separator: "|") }
    let a: Learning.ID
    let b: Learning.ID
    /// The shared normalized subject (their title), for display.
    let subject: String
}

enum MemoryHygiene {

    /// Days after which an unused learning is "aging", then "stale". Tuned conservatively —
    /// growth slope, not age alone, is what bankrupts a long-lived store, so we only nudge.
    static let agingAfterDays = 60
    static let staleAfterDays = 120

    /// Staleness of one learning as of `now`. Pinned entries never go stale (the user has
    /// explicitly said "always keep"). Recency is measured from the last time it was actually
    /// applied, falling back to when it was created.
    static func staleness(_ l: Learning, now: Date) -> MemoryStaleness {
        if l.pinned { return .fresh }
        let lastRelevant = l.lastAppliedAt ?? l.createdAt
        let days = Calendar.current.dateComponents([.day], from: lastRelevant, to: now).day ?? 0
        if days >= staleAfterDays { return .stale }
        if days >= agingAfterDays { return .aging }
        return .fresh
    }

    /// The learnings worth surfacing for a "keep or forget?" review — stale and never pinned.
    static func staleLearnings(_ all: [Learning], now: Date) -> [Learning] {
        all.filter { staleness($0, now: now) == .stale }
    }

    /// Conflicting pairs: two entries about the SAME subject (normalized title) and SAME scope
    /// that did NOT dedupe — which only happens when their KIND differs (e.g. a `pattern` and a
    /// `mistake` about the same thing) or their guidance body diverges. That's conflicting
    /// advice on one subject; surface it. Same-kind+title+scope already collapse on write, so
    /// they never reach here.
    static func conflicts(_ all: [Learning]) -> [MemoryConflict] {
        var groups: [String: [Learning]] = [:]
        for l in all {
            let subject = normalizedTitle(l.title)
            guard !subject.isEmpty else { continue }
            let key = subject + "\u{1}" + (l.repoScope ?? "")
            groups[key, default: []].append(l)
        }
        var out: [MemoryConflict] = []
        for (_, group) in groups where group.count >= 2 {
            // Only a real conflict if they actually disagree (different kind or different body).
            let kinds = Set(group.map(\.kind))
            let bodies = Set(group.map { normalizedTitle($0.body) })
            guard kinds.count > 1 || bodies.count > 1 else { continue }
            // Pair the two most recent — enough to prompt a decision without noise.
            let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
            out.append(MemoryConflict(a: sorted[0].id, b: sorted[1].id,
                                      subject: sorted[0].title))
        }
        return out.sorted { $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending }
    }

    /// Normalize a title/body for subject matching: lowercased, trimmed, collapsed whitespace.
    static func normalizedTitle(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
