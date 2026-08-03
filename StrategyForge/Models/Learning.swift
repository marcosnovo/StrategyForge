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

/// Which of the two memory levels a learning belongs to.
///
/// Factory's User+Org split is the parity gap the competitive analysis flagged, and it's a
/// real distinction rather than a tag: a `team` learning is a shared convention that reads
/// as POLICY — it outranks personal preference when both apply, and it is never dropped to
/// make room in a digest. A `user` learning is how *you* like to work on this Mac.
///
/// There is no server behind this. "Team" means the learnings you'd share with the people
/// you work with (and that roam with you via sync); Coral has no org accounts to enforce.
enum LearningScope: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case user
    case team

    var id: String { rawValue }
    var displayKey: String { "memory.scope.\(rawValue)" }
    var helpKey: String { "memory.scope.\(rawValue).help" }
    var icon: String { self == .team ? "person.2.fill" : "person.fill" }
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
    /// Which memory LEVEL this belongs to — yours, or the team's shared policy.
    var scope: LearningScope
    var source: LearningSource
    var createdAt: Date
    /// Last edit time — the last-writer-wins key for cross-device sync. Defaults to
    /// createdAt for entries saved before this field existed.
    var updatedAt: Date
    /// How many times this learning has been injected into a generated file — a light
    /// usefulness signal for ranking.
    var timesApplied: Int
    /// Pinned learnings always sort first and are always eligible for injection.
    var pinned: Bool

    init(id: UUID = UUID(), kind: LearningKind, title: String, body: String = "",
         tags: [String] = [], repoScope: String? = nil, scope: LearningScope = .user,
         source: LearningSource, createdAt: Date = Date(), updatedAt: Date? = nil,
         timesApplied: Int = 0, pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.tags = tags
        self.repoScope = repoScope
        self.scope = scope
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.timesApplied = timesApplied
        self.pinned = pinned
    }

    // Tolerant decode so older saved data (without newer keys) still loads — the same
    // per-field `decodeIfPresent ?? default` idiom as AppSettings.
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, tags, repoScope, scope, source, createdAt, updatedAt, timesApplied, pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(LearningKind.self, forKey: .kind) ?? .pattern
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        repoScope = try c.decodeIfPresent(String.self, forKey: .repoScope)
        // Everything saved before the two levels existed was personal.
        let scopeRaw = ((try? c.decodeIfPresent(String.self, forKey: .scope)) ?? nil) ?? ""
        scope = LearningScope(rawValue: scopeRaw) ?? .user
        source = try c.decodeIfPresent(LearningSource.self, forKey: .source)
            ?? LearningSource(origin: .manual)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        timesApplied = try c.decodeIfPresent(Int.self, forKey: .timesApplied) ?? 0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    /// Dedupe identity: same kind + same normalized title + same repo scope is "the same
    /// learning" (so promoting the same Review finding twice doesn't pile up).
    /// The LEVEL is part of it too: promoting a personal note to a team
    /// convention must not silently collapse into the personal one — they say different
    /// things about how binding the rule is.
    var dedupeKey: String {
        "\(kind.rawValue)|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(repoScope ?? "")|\(scope.rawValue)"
    }
}
