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
    /// Localization key for "what starts / triggers each cycle".
    var startsKey: String { "loop.kind.\(rawValue).starts" }
    /// Localization key for "when it stops repeating".
    var untilKey: String { "loop.kind.\(rawValue).until" }
    /// Legend rows (Start / Trigger / Rule / Stop) — the shared spec-sheet skeleton
    /// that makes each kind's purpose unmistakable.
    var legendStartKey: String { "loop.kind.\(rawValue).legend.start" }
    var legendTriggerKey: String { "loop.kind.\(rawValue).legend.trigger" }
    var legendRuleKey: String { "loop.kind.\(rawValue).legend.rule" }
    var legendStopKey: String { "loop.kind.\(rawValue).legend.stop" }
    /// Honest cadence footer key (uses the plan's real maxTurns / intervalMinutes).
    var cadenceKey: String { "loop.cadence.\(rawValue)" }

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

/// A non-destructive snapshot taken after a loop iteration's work (a `git stash
/// create` SHA), so a run can be rewound to that point.
struct LoopCheckpoint: Identifiable, Hashable {
    let id = UUID()
    let iteration: Int
    let sha: String
    let reason: String?
    let at: Date
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
    /// Optional spend cap in USD for a goal loop's `loop.sh`: it tallies each turn's
    /// reported cost and stops before this is exceeded. `nil` = no cap (the article's
    /// "a loop with no dollar abort is a bill"). Only emitted for goal loops.
    var budgetUSD: Double?
    /// How hard the worker model thinks — written into `loop.sh`/the launch command
    /// as `--effort`. Effort is the cheapest routing dial: same model, more thinking.
    var effort: CostEffort
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

    // MARK: Lifetime health (the article's "cost per accepted change")
    //
    // The metric that decides whether a loop is worth running is NOT tokens spent or
    // turns attempted — it's *cost per accepted change*, and if fewer than half the
    // runs are accepted you're doing the review the loop was meant to remove. Coral's
    // objective gate IS the verifier, so an "accepted change" = a run that ended in a
    // verified PASS. These three lifetime counters (updated once per finished run) are
    // all we need to surface that health; no per-run history is persisted.

    /// Total finished runs over the loop's life.
    var lifetimeRuns: Int
    /// Runs that ended in a verified PASS (an accepted change).
    var lifetimeAccepted: Int
    /// Total reported spend across all finished runs, USD.
    var lifetimeCostUSD: Double

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
        budgetUSD: Double? = nil,
        effort: CostEffort = .medium,
        intervalMinutes: Int = 30,
        workerModel: ClaudeModel = .sonnet5,
        verifierEnabled: Bool = true,
        verifierModel: ClaudeModel = .haiku45,
        memoryEnabled: Bool = true,
        repoPath: String? = nil,
        repoBookmark: Data? = nil,
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil,
        lastRun: LoopRunSummary? = nil,
        lifetimeRuns: Int = 0,
        lifetimeAccepted: Int = 0,
        lifetimeCostUSD: Double = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.goal = goal
        self.neverTouch = neverTouch
        self.stopIf = stopIf
        self.maxTurns = Self.clampTurns(maxTurns)
        self.budgetUSD = budgetUSD.map { max(0, $0) }
        self.effort = effort
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
        self.lifetimeRuns = max(0, lifetimeRuns)
        self.lifetimeAccepted = max(0, lifetimeAccepted)
        self.lifetimeCostUSD = max(0, lifetimeCostUSD)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, goal, neverTouch, stopIf, maxTurns, budgetUSD, effort, intervalMinutes
        case workerModel, verifierEnabled, verifierModel, memoryEnabled
        case repoPath, repoBookmark, updatedAt, lastRunAt, lastRun
        case lifetimeRuns, lifetimeAccepted, lifetimeCostUSD
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
        budgetUSD = (try? c.decodeIfPresent(Double.self, forKey: .budgetUSD) ?? nil).map { max(0, $0) }
        let effortRaw = ((try? c.decodeIfPresent(String.self, forKey: .effort)) ?? nil) ?? ""
        effort = CostEffort(rawValue: effortRaw) ?? .medium
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
        lifetimeRuns = max(0, try c.decodeIfPresent(Int.self, forKey: .lifetimeRuns) ?? 0)
        lifetimeAccepted = max(0, try c.decodeIfPresent(Int.self, forKey: .lifetimeAccepted) ?? 0)
        lifetimeCostUSD = max(0, try c.decodeIfPresent(Double.self, forKey: .lifetimeCostUSD) ?? 0)
    }

    // MARK: - Validation

    /// Problems with the plan, as localization KEYS ("loop.issue.*"). Empty name
    /// and empty goal are errors; a goal loop without an independent verifier is
    /// a warning (it would grade its own work).
    func validate() -> [String] {
        var issues: [String] = []
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("loop.issue.name")
        }
        if trimmedGoal.isEmpty {
            issues.append("loop.issue.goal")
        } else if !Self.isVerifiableGoal(trimmedGoal) {
            // Warning, not an error: a loop closes on "## Done when", so a goal a
            // shell can't check means the verifier is grading vibes (article law:
            // "done is a fact about the environment").
            issues.append("loop.issue.vagueGoal")
        }
        if kind == .goalBased && !verifierEnabled {
            issues.append("loop.issue.noVerifier")
        }
        return issues
    }

    /// Heuristic: does the goal read as machine-checkable? Lenient on purpose (it
    /// only drives a soft warning) — a goal that names a test/build/lint signal, a
    /// pass/exit condition, a number, or an inline `command` counts as verifiable.
    /// Matches EN + ES markers, diacritics folded.
    static func isVerifiableGoal(_ goal: String) -> Bool {
        let text = goal.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        if text.contains("`") { return true }                 // an inline command
        if text.range(of: "[0-9]", options: .regularExpression) != nil { return true }
        let markers = [
            "test", "lint", "build", "compil", "pass", "pasa", "green", "verde",
            "exit", "grep", "coverage", "cobertura", "benchmark", "error", "sin errores",
            "no errors", "deploy", "assert", "snapshot", "typecheck", "tsc", "xcodebuild",
            "npm", "cargo", "returns", "devuelve", "%", "until", "hasta",
        ]
        return markers.contains { text.contains($0) }
    }

    /// True when the loop can actually run: it has a target repo and a goal.
    var isRunnable: Bool {
        (repoPath != nil || repoBookmark != nil)
            && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The loop's health, the article's real success metric: cost per accepted change
    /// and the share of runs that were accepted. `nil` until at least one run finishes.
    var health: LoopHealth? {
        guard lifetimeRuns > 0 else { return nil }
        return LoopHealth(runs: lifetimeRuns, accepted: lifetimeAccepted, costUSD: lifetimeCostUSD)
    }
}

/// A loop's running health, derived from its lifetime counters. Pure/testable.
struct LoopHealth: Hashable {
    let runs: Int
    let accepted: Int
    let costUSD: Double

    /// Share of finished runs that ended in a verified PASS (0…1).
    var acceptanceRate: Double { runs > 0 ? Double(accepted) / Double(runs) : 0 }

    /// Cost per accepted change — total spend ÷ accepted runs. `nil` when nothing has
    /// been accepted yet (dividing by zero would read as "free", which is a lie).
    var costPerAccepted: Double? { accepted > 0 ? costUSD / Double(accepted) : nil }

    /// Enough runs to trust the rate (a single fluke shouldn't raise an alarm).
    var hasEnoughData: Bool { runs >= 3 }

    /// The article's warning line: below a 50% accept rate, the loop is losing — you're
    /// doing the review it was meant to remove. Only fires once there's enough data.
    var isUnderperforming: Bool { hasEnoughData && acceptanceRate < 0.5 }
}
