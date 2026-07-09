//
//  CostEstimationHooks.swift
//  StrategyForge
//
//  Approximate, relative cost estimation per strategy. This is NOT a billing
//  figure — it's a rough "how expensive is this shape" signal so a user can
//  compare strategies (Solo is cheap, a big Domain team is pricey) and see which
//  model drives the cost. Pure and testable; no network.
//

import Foundation

/// A rough cost estimate for running a strategy once on a medium task.
struct StrategyCost {
    /// Approximate USD for one task/run.
    let perRun: Double
    /// Contribution per model (USD), for the breakdown.
    let byModel: [ClaudeModel: Double]

    enum Tier { case low, medium, high }

    /// Relative bucket for a quick glance.
    var tier: Tier {
        switch perRun {
        case ..<2:  return .low
        case ..<5:  return .medium
        default:    return .high
        }
    }
}

/// How thorough Claude works on a request. Per the model-vs-effort model, effort
/// scales token usage (higher effort ≈ more reading/verifying/thinking). This is
/// used ONLY to make the cost estimate more realistic — it is never written to any
/// generated file. `medium` is the baseline (×1) so estimates are stable by default.
enum CostEffort: String, CaseIterable, Identifiable, Hashable {
    case low, medium, high
    var id: String { rawValue }

    /// Token multiplier applied to each role's workload.
    var multiplier: Double {
        switch self {
        case .low:    return 0.4
        case .medium: return 1.0
        case .high:   return 2.8
        }
    }

    var labelKey: String { "effort.\(rawValue)" }
}

enum CostEstimator {

    /// Rough tokens a role consumes/produces on one medium task. The orchestrator
    /// (main session) emits comparatively few tokens while deciding; workers do the
    /// heavy lifting; advisory roles read a lot and write little.
    private struct Workload { let input: Double; let output: Double }

    private static func workload(isOrchestrator: Bool, role: RoleKind) -> Workload {
        if isOrchestrator { return Workload(input: 40_000, output: 15_000) }
        switch role {
        case .advisor, .reviewer, .researcher:
            return Workload(input: 60_000, output: 20_000)
        default: // worker, planner, specialist, (orchestrator handled above)
            return Workload(input: 90_000, output: 45_000)
        }
    }

    /// Estimate the cost of running `strategy` once at the baseline (medium) effort.
    static func estimate(_ strategy: Strategy) -> StrategyCost {
        estimate(strategy, effort: .medium)
    }

    /// Estimate the cost of running `strategy` once at a given effort level. Effort
    /// scales every role's token workload; it does not change model pricing.
    static func estimate(_ strategy: Strategy, effort: CostEffort) -> StrategyCost {
        var total = 0.0
        var byModel: [ClaudeModel: Double] = [:]
        let m = effort.multiplier

        for role in strategy.roles {
            guard let price = Constants.pricing[role.model.rawValue] else { continue }
            let load = workload(isOrchestrator: role.isOrchestrator, role: role.role)
            let count = Double(max(role.count, 1))
            let cost = count * (load.input * m / 1_000_000 * price.inputPerM
                              + load.output * m / 1_000_000 * price.outputPerM)
            total += cost
            byModel[role.model, default: 0] += cost
        }

        return StrategyCost(perRun: total, byModel: byModel)
    }
}
