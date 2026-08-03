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
    /// Approximate total tokens (input + output) for one run — the headline figure.
    let perRunTokens: Int
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

    /// Compact token count, e.g. "1.2M" or "135k".
    var tokensShort: String {
        if perRunTokens >= 1_000_000 { return String(format: "%.1fM", Double(perRunTokens) / 1_000_000) }
        if perRunTokens >= 1_000 { return "\(perRunTokens / 1_000)k" }
        return "\(perRunTokens)"
    }
    var usdShort: String { String(format: "$%.2f", perRun) }
    /// The headline cost, tokens first with the dollar figure in parentheses.
    var headline: String { "~\(tokensShort) (\(usdShort))" }
}

/// How thorough Claude works on a request. Per the model-vs-effort model, effort
/// scales token usage (higher effort ≈ more reading/verifying/thinking). This is
/// used ONLY to make the cost estimate more realistic — it is never written to any
/// generated file. `medium` is the baseline (×1) so estimates are stable by default.
enum CostEffort: String, CaseIterable, Identifiable, Hashable, Codable {
    case low, medium, high
    var id: String { rawValue }

    /// The value passed to Claude Code's `--effort` flag. The three estimate levels
    /// map 1:1 onto the CLI's lower three (`low|medium|high`); the CLI also accepts
    /// `xhigh|max`, which the loop editor doesn't expose.
    var cliValue: String { rawValue }

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

    /// Rough tokens a role consumes/produces on one medium task. Workers do the
    /// heavy lifting; advisory roles read a lot and write little.
    ///
    /// The orchestrator's own load is dominated by *what it decides not to do
    /// itself*. With a team to delegate to, it mostly plans, briefs and reviews —
    /// a light load. With NO subagents (a solo config), it reads, implements and
    /// verifies everything itself, so it carries a full worker load. Pricing the
    /// solo lead as if it delegated understates its cost — the whole point of the
    /// delegation economics is that the lead's token bill tracks how much it hands
    /// off, not just its per-token price.
    /// Rough input/output tokens for one role on one medium task. Internal (not private)
    /// so `GraphCostLens` prices the same nodes this estimator does — two independent
    /// workload tables would drift and quietly disagree in the UI.
    struct Workload { let input: Double; let output: Double }

    static func workload(isOrchestrator: Bool, role: RoleKind, canDelegate: Bool) -> Workload {
        if isOrchestrator {
            return canDelegate
                ? Workload(input: 40_000, output: 15_000)   // delegates → light
                : Workload(input: 90_000, output: 45_000)   // solo → does the work itself
        }
        switch role {
        case .advisor, .reviewer, .researcher:
            return Workload(input: 60_000, output: 20_000)
        default: // worker, planner, specialist, (orchestrator handled above)
            return Workload(input: 90_000, output: 45_000)
        }
    }

    /// USD for one model call of `input`/`output` tokens on `model`. Input dominates an
    /// agent's bill (~100:1 read:write) and much of it is a repeated prefix served from
    /// cache, so the cached share is priced at the cache-read rate and only the rest at
    /// the fresh-input rate; tokenizer overhead lifts the effective spend above sticker.
    /// Returns 0 for a model with no known pricing.
    static func callCostUSD(input: Double, output: Double, model: ClaudeModel) -> Double {
        guard let price = Constants.pricing[model.rawValue] else { return 0 }
        let cachedIn = input * Constants.CostModel.cachedInputFraction
        let freshIn = input - cachedIn
        let inputCost = (freshIn * price.inputPerM
                         + cachedIn * price.inputPerM * Constants.CostModel.cacheReadMultiplier) / 1_000_000
        let outputCost = output / 1_000_000 * price.outputPerM
        return (inputCost + outputCost) * Constants.CostModel.tokenizerOverhead
    }

    /// USD per million FRESH input tokens on `model` (no cache discount) — what re-reading
    /// an upstream result costs when it travels through a model instead of through code.
    static func freshInputPerMillion(_ model: ClaudeModel) -> Double {
        (Constants.pricing[model.rawValue]?.inputPerM ?? 0) * Constants.CostModel.tokenizerOverhead
    }

    /// Estimate the cost of running `strategy` once at the baseline (medium) effort.
    static func estimate(_ strategy: Strategy) -> StrategyCost {
        estimate(strategy, effort: .medium)
    }

    /// Estimate the cost of running `strategy` once at a given effort level. Effort
    /// scales every role's token workload; it does not change model pricing.
    static func estimate(_ strategy: Strategy, effort: CostEffort) -> StrategyCost {
        var total = 0.0
        var tokens = 0.0
        var byModel: [ClaudeModel: Double] = [:]
        let m = effort.multiplier
        // Whether the orchestrator has anyone to delegate to. Drives how much of the
        // work the lead does itself (see `workload`).
        let canDelegate = strategy.roles.contains { !$0.isOrchestrator }

        for role in strategy.roles {
            guard Constants.pricing[role.model.rawValue] != nil else { continue }
            let load = workload(isOrchestrator: role.isOrchestrator, role: role.role, canDelegate: canDelegate)
            let count = Double(max(role.count, 1))
            let cost = count * callCostUSD(input: load.input * m, output: load.output * m, model: role.model)

            total += cost
            tokens += count * (load.input + load.output) * m
            byModel[role.model, default: 0] += cost
        }

        return StrategyCost(perRun: total, perRunTokens: Int(tokens), byModel: byModel)
    }
}
