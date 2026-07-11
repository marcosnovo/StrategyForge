//
//  LoopPlan.swift
//  StrategyForge
//
//  The data model for the Loop Builder: a work loop (goal → act → verify →
//  iterate) with an INDEPENDENT verifier subagent (the maker never grades its
//  own work), a verifiable "done when" condition, a hard turn limit as the
//  emergency brake, and a STATE.md memory file so run N+1 resumes instead of
//  restarting.
//

import Foundation

/// The four loop shapes. The raw value is the stable persisted id.
enum LoopKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case turnBased, goalBased, timeBased, proactive

    var id: String { rawValue }

    /// Localization key for the kind's display name ("loop.kind.turnBased" …).
    var labelKey: String { "loop.kind.\(rawValue)" }
    /// Localization key for the one-line explanation.
    var blurbKey: String { "loop.kind.\(rawValue).blurb" }
    /// Localization key for the "suits …" hint.
    var suitsKey: String { "loop.kind.\(rawValue).suits" }

    /// The cycle spelled out — a literal, not localized: it names the stages the
    /// same way the generated files and the diagram do.
    var flow: String {
        switch self {
        case .turnBased: return "Prompt → Work → Check → Reply"
        case .goalBased: return "Goal → Try → Judge → Done"
        case .timeBased: return "Interval → Check → React → Wait"
        case .proactive: return "Event → Route → Work → Review"
        }
    }

    /// SF Symbol conveying the kind at a glance.
    var icon: String {
        switch self {
        case .turnBased: return "person.line.dotted.person"
        case .goalBased: return "target"
        case .timeBased: return "clock.arrow.circlepath"
        case .proactive: return "bolt.badge.clock"
        }
    }
}

/// The persisted outcome of a loop's most recent run, shown when the loop is
/// idle ("last run: PASS · 3 turns · 2h ago").
struct LoopRunSummary: Codable, Hashable {
    var date: Date
    /// true = verified PASS, false = failed/out of turns, nil = done unverified.
    var pass: Bool?
    /// The verifier's one-line reason (or the run's error), if any.
    var reason: String?
    var iterations: Int
    var tokens: Int
    var costUSD: Double
}

/// A saved loop: what "done" means, the guardrails, the worker/verifier pair,
/// and the repo it targets. Persisted as JSON by `LoopStore`.
struct LoopPlan: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: LoopKind
    /// The verifiable "done when" condition — the loop's contract.
    var goal: String
    /// Newline list of paths/areas the loop must never modify. May be empty.
    var neverTouch: String
    /// Extra stop conditions beyond the turn limit. May be empty.
    var stopIf: String
    /// Hard emergency brake. Clamped to 1...100 on init/decode.
    var maxTurns: Int
    /// Cadence for `timeBased` loops, in minutes.
    var intervalMinutes: Int
    /// The model that does the work.
    var workerModel: ClaudeModel
    /// Whether an independent verifier subagent grades each iteration.
    var verifierEnabled: Bool
    /// The verifier's model (cheap and fast by default — judging is easier than making).
    var verifierModel: ClaudeModel
    /// Whether a STATE.md memory file carries context between runs.
    var memoryEnabled: Bool
    /// POSIX path of the target repo, for display. Nil until the user picks one.
    var repoPath: String?
    /// Security-scoped bookmark for the repo folder, so write access persists.
    var repoBookmark: Data?
    var updatedAt: Date
    var lastRunAt: Date?
    /// Outcome of the most recent finished run (nil until a run finishes).
    var lastRun: LoopRunSummary?

    /// Clamp the emergency brake to a sane range.
    static func clampTurns(_ n: Int) -> Int { min(max(n, 1), 100) }

    init(
        id: UUID = UUID(),
        name: String = "",
        kind: LoopKind = .goalBased,
        goal: String = "",
        neverTouch: String = "",
        stopIf: String = "",
        maxTurns: Int = 20,
        intervalMinutes: Int = 30,
        workerModel: ClaudeModel = .sonnet5,
        verifierEnabled: Bool = true,
        verifierModel: ClaudeModel = .haiku45,
        memoryEnabled: Bool = true,
        repoPath: String? = nil,
        repoBookmark: Data? = nil,
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil,
        lastRun: LoopRunSummary? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.goal = goal
        self.neverTouch = neverTouch
        self.stopIf = stopIf
        self.maxTurns = Self.clampTurns(maxTurns)
        self.intervalMinutes = intervalMinutes
        self.workerModel = workerModel
        self.verifierEnabled = verifierEnabled
        self.verifierModel = verifierModel
        self.memoryEnabled = memoryEnabled
        self.repoPath = repoPath
        self.repoBookmark = repoBookmark
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
        self.lastRun = lastRun
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, goal, neverTouch, stopIf, maxTurns, intervalMinutes
        case workerModel, verifierEnabled, verifierModel, memoryEnabled
        case repoPath, repoBookmark, updatedAt, lastRunAt, lastRun
    }

    // Tolerant decode: missing keys fall back to defaults (mirrors Configuration),
    // so a plan saved by an older or newer app version never fails the whole store.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        // Tolerate unknown kind rawValues from newer app versions.
        let kindRaw = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? ""
        kind = LoopKind(rawValue: kindRaw) ?? .goalBased
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        neverTouch = try c.decodeIfPresent(String.self, forKey: .neverTouch) ?? ""
        stopIf = try c.decodeIfPresent(String.self, forKey: .stopIf) ?? ""
        maxTurns = Self.clampTurns(try c.decodeIfPresent(Int.self, forKey: .maxTurns) ?? 20)
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 30
        let workerRaw = ((try? c.decodeIfPresent(String.self, forKey: .workerModel)) ?? nil) ?? ""
        workerModel = ClaudeModel(rawValue: workerRaw) ?? .sonnet5
        verifierEnabled = try c.decodeIfPresent(Bool.self, forKey: .verifierEnabled) ?? true
        let verifierRaw = ((try? c.decodeIfPresent(String.self, forKey: .verifierModel)) ?? nil) ?? ""
        verifierModel = ClaudeModel(rawValue: verifierRaw) ?? .haiku45
        memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? true
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath)
        repoBookmark = try c.decodeIfPresent(Data.self, forKey: .repoBookmark)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastRun = ((try? c.decodeIfPresent(LoopRunSummary.self, forKey: .lastRun)) ?? nil)
    }

    // MARK: - Validation

    /// Problems with the plan, as localization KEYS ("loop.issue.*"). Empty name
    /// and empty goal are errors; a goal loop without an independent verifier is
    /// a warning (it would grade its own work).
    func validate() -> [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("loop.issue.name")
        }
        if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("loop.issue.goal")
        }
        if kind == .goalBased && !verifierEnabled {
            issues.append("loop.issue.noVerifier")
        }
        return issues
    }

    /// True when the loop can actually run: it has a target repo and a goal.
    var isRunnable: Bool {
        (repoPath != nil || repoBookmark != nil)
            && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
