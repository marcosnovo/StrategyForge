//
//  Learning.swift
//  StrategyForge
//
//  One durable "learning" in Coral's cross-project knowledge base — a pattern,
//  decision, or mistake that survives a single loop and can be injected into future
//  runs so teams improve over time (the metaswarm-style knowledge base, but Coral's:
//  local-first, honest). Unlike the per-loop STATE.md (which lives in one repo and
//  accumulates across runs of THE SAME loop), a Learning is global to the user and can
//  feed any team's generated CLAUDE.md.
//
//  Honesty guarantee: every Learning carries a non-optional `source` describing where
//  it actually came from (a Review finding, a Mission Report, a parsed STATE.md, or an
//  explicit manual entry). There is no "LLM made this up" origin — nothing is stored
//  without real provenance.
//

import Foundation

enum LearningKind: String, Codable, CaseIterable, Sendable, Hashable {
    case pattern     // a reusable approach that worked ("prefer X over Y here")
    case decision    // a settled choice + its rationale
    case mistake     // a pitfall to avoid ("don't regenerate fixtures")

    var displayKey: String { "memory.kind.\(rawValue)" }
    var icon: String {
        switch self {
        case .pattern: return "square.grid.2x2"
        case .decision: return "signpost.right"
        case .mistake: return "exclamationmark.triangle"
        }
    }
}

/// Where a learning came from — the provenance that makes the knowledge base honest.
struct LearningSource: Codable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable { case manual, review, missionReport, stateFile }
    var origin: Origin
    /// Human context for the origin, e.g. "AuthService.swift · warning", a repo name,
    /// or a strategy name. Free text; may be empty for `.manual`.
    var detail: String = ""

    init(origin: Origin, detail: String = "") { self.origin = origin; self.detail = detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? .manual
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
    }
}

struct Learning: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: LearningKind
    var title: String
    var body: String
    /// Lowercased tokens (language / framework / repo / topic) used to match a learning
    /// to a future run's context.
    var tags: [String]
    /// nil = applies globally; otherwise scoped to this repo path/name.
    var repoScope: String?
    var source: LearningSource
    var createdAt: Date
    /// Last edit time — the last-writer-wins key for cross-device sync. Defaults to
    /// createdAt for entries saved before this field existed.
    var updatedAt: Date
    /// How many times this learning has been injected into a generated file — a light
    /// usefulness signal for ranking.
    var timesApplied: Int
    /// When it was last injected into a run — the "still relevant?" signal for staleness
    /// (a memory nobody has used in months is a candidate to forget). nil = never applied.
    var lastAppliedAt: Date?
    /// Pinned learnings always sort first and are always eligible for injection.
    var pinned: Bool
    /// Human-reviewed = canonical (the "operational truth layer": knowledge enters the corpus
    /// through review, not auto-save). Only reviewed (or pinned / manual) learnings are injected
    /// into agents — auto-harvested ones wait as "pending" until a human approves them, so a
    /// wrong lesson can't silently compound across every future run. Manual entries are trusted.
    var reviewed: Bool

    init(id: UUID = UUID(), kind: LearningKind, title: String, body: String = "",
         tags: [String] = [], repoScope: String? = nil,
         source: LearningSource, createdAt: Date = Date(), updatedAt: Date? = nil,
         timesApplied: Int = 0, lastAppliedAt: Date? = nil, pinned: Bool = false, reviewed: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.tags = tags
        self.repoScope = repoScope
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.timesApplied = timesApplied
        self.lastAppliedAt = lastAppliedAt
        self.pinned = pinned
        self.reviewed = reviewed
    }

    // Tolerant decode so older saved data (without newer keys) still loads — the same
    // per-field `decodeIfPresent ?? default` idiom as AppSettings.
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, tags, repoScope, source, createdAt, updatedAt, timesApplied, lastAppliedAt, pinned, reviewed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(LearningKind.self, forKey: .kind) ?? .pattern
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        repoScope = try c.decodeIfPresent(String.self, forKey: .repoScope)
        source = try c.decodeIfPresent(LearningSource.self, forKey: .source)
            ?? LearningSource(origin: .manual)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        timesApplied = try c.decodeIfPresent(Int.self, forKey: .timesApplied) ?? 0
        lastAppliedAt = try c.decodeIfPresent(Date.self, forKey: .lastAppliedAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        // Grandfather entries saved before review existed → treated as reviewed (don't silently
        // drop knowledge the user already relied on).
        reviewed = try c.decodeIfPresent(Bool.self, forKey: .reviewed) ?? true
    }

    /// Dedupe identity: same kind + same normalized title + same scope is "the same
    /// learning" (so promoting the same Review finding twice doesn't pile up).
    var dedupeKey: String {
        "\(kind.rawValue)|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(repoScope ?? "")"
    }
}

/// An audit-trail entry: what happened to the knowledge base, and when. A wrong memory
/// persists into every future run that reads it, so control means keeping the learning
/// observable — export, inspect, roll back (Anthropic's memory-control guidance).
struct MemoryEvent: Identifiable, Codable, Hashable, Sendable {
    enum Action: String, Codable, Sendable {
        case added, approved, edited, pinned, unpinned, deleted, forgotten
        var labelKey: String { "memory.audit.\(rawValue)" }
        var icon: String {
            switch self {
            case .added:     return "plus.circle"
            case .approved:  return "checkmark.seal"
            case .edited:    return "pencil"
            case .pinned:    return "pin.fill"
            case .unpinned:  return "pin.slash"
            case .deleted:   return "trash"
            case .forgotten: return "wind"
            }
        }
    }
    var id: UUID = UUID()
    var action: Action
    /// Snapshot of the learning's title at the time (so the log is readable even after delete).
    var title: String
    var at: Date
}
