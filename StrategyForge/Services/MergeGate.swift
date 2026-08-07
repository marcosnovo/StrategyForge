//
//  MergeGate.swift
//  StrategyForge
//
//  "Build the gate that lets your agents merge without you" (Eval Engineering, 2026). The gate
//  reads EVIDENCE in a fixed order and has a rule for it — it does not read confidence:
//
//    1. Blast radius   — irreversible NEVER opens, regardless of any score (BlastRadius).
//    2. Deterministic  — tests / types / build / schema. No model involved → trusted most.
//    3. Review + path  — blocking findings from the INDEPENDENT reviewer, and whether the
//                        trajectory was clean (a right answer reached the wrong way is a fail).
//    4. History        — how often this agent's work on this surface was rolled back before.
//    5. Self-assessment— the model's own opinion, weighted LEAST (it's the one input the model
//                        can influence), and only ever used to DOWNGRADE, never to open a lane.
//
//  Pure + deterministic, so it's unit-tested; the UI turns the verdict into an advisory (shadow)
//  or an actual merge affordance. Never auto-merges an irreversible lane.
//

import Foundation

/// What the gate permits for a change.
enum MergeDecision: String, Sendable, Equatable {
    case autoMerge      // evidence clears the bar for this lane — may merge without a human
    case needsReview    // a human must read it before it goes in
    case blocked        // must not auto-merge under any score (irreversible / failing checks)

    var labelKey: String { "gate.decision.\(rawValue)" }
}

/// The evidence the gate reads. Optionals mean "not available" (e.g. no test run yet), which the
/// gate treats conservatively — absence of a deterministic pass never counts as a pass.
struct MergeEvidence: Sendable, Equatable {
    var blast: BlastAssessment
    /// Deterministic checks (tests/types/build/schema): true = all passed, false = something
    /// failed, nil = none were run.
    var deterministicPassed: Bool? = nil
    /// High-severity findings from the independent reviewer (blocking).
    var blockingFindings: Int = 0
    /// Was the path sound? false = thrashed / wrong tools, nil = not graded.
    var trajectoryClean: Bool? = nil
    /// How many times this agent's work on this surface was rolled back before.
    var priorRollbacks: Int = 0
    /// The model's own 0…1 confidence — weighted LEAST; only ever downgrades.
    var selfAssessment: Double? = nil
}

/// The gate's verdict: the decision, the ordered evidence reasons, and which tier decided.
struct MergeVerdict: Sendable, Equatable {
    var decision: MergeDecision
    var reasons: [String]
    /// The evidence tier that set the decision (for the UI to explain "why").
    var decidingTier: String
}

enum MergeGate {

    /// Rollbacks at/above this count on a surface make even a clean change need a human.
    static let rollbackReviewThreshold = 2
    /// Below this self-assessment, downgrade an otherwise-auto lane to review.
    static let lowSelfAssessment = 0.5

    /// Evaluate the evidence into a verdict. `shadow` mode never returns `.autoMerge` (the gate
    /// scores every change but merges none — run it alongside humans until they agree), while
    /// still computing the merit decision so callers can log the would-be outcome.
    static func evaluate(_ e: MergeEvidence, shadow: Bool = false) -> MergeVerdict {
        let merit = meritVerdict(e)
        guard shadow, merit.decision == .autoMerge else { return merit }
        return MergeVerdict(decision: .needsReview,
                            reasons: merit.reasons + ["shadow mode: would auto-merge, held for review"],
                            decidingTier: "shadow")
    }

    private static func meritVerdict(_ e: MergeEvidence) -> MergeVerdict {
        var reasons: [String] = []

        // 1. Blast radius — irreversible never opens.
        if e.blast.radius == .irreversible {
            return MergeVerdict(decision: .blocked,
                                reasons: ["irreversible change (\(e.blast.reasons.first ?? "hard to undo")) — a human must review"],
                                decidingTier: "blast-radius")
        }
        reasons.append("blast radius: \(e.blast.radius.rawValue)")

        // 2. Deterministic checks — a failure blocks; their absence can't count as a pass.
        if e.deterministicPassed == false {
            return MergeVerdict(decision: .blocked, reasons: reasons + ["deterministic checks failed"],
                                decidingTier: "deterministic")
        }
        let deterministicOK = (e.deterministicPassed == true)
        reasons.append(deterministicOK ? "deterministic checks passed" : "no deterministic checks run")

        // 3. Independent review + trajectory.
        if e.blockingFindings > 0 {
            return MergeVerdict(decision: .needsReview,
                                reasons: reasons + ["\(e.blockingFindings) blocking review finding(s)"],
                                decidingTier: "review")
        }
        if e.trajectoryClean == false {
            return MergeVerdict(decision: .needsReview, reasons: reasons + ["trajectory wasn't clean"],
                                decidingTier: "trajectory")
        }

        // 4. History — a repeatedly-rolled-back surface needs eyes.
        if e.priorRollbacks >= rollbackReviewThreshold {
            return MergeVerdict(decision: .needsReview,
                                reasons: reasons + ["rolled back \(e.priorRollbacks)× on this surface before"],
                                decidingTier: "history")
        }

        // Lane rules: contained can open on deterministic pass; wide also needs a clean path.
        var decision: MergeDecision
        switch e.blast.radius {
        case .contained:
            decision = deterministicOK ? .autoMerge : .needsReview
        case .wide:
            decision = (deterministicOK && e.trajectoryClean == true) ? .autoMerge : .needsReview
            if decision == .needsReview { reasons.append("wide surface needs passing checks + a clean trajectory") }
        case .irreversible:
            decision = .blocked   // unreachable (handled above)
        }

        // 5. Self-assessment — weighted least; only ever downgrades an auto lane.
        if decision == .autoMerge, let s = e.selfAssessment, s < lowSelfAssessment {
            return MergeVerdict(decision: .needsReview,
                                reasons: reasons + [String(format: "the agent's own confidence is low (%.0f%%)", s * 100)],
                                decidingTier: "self-assessment")
        }

        reasons.append(decision == .autoMerge ? "clears the bar for this lane" : "needs a human before it goes in")
        return MergeVerdict(decision: decision, reasons: reasons, decidingTier: "lane")
    }
}
