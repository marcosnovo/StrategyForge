//
//  ArenaCostEstimator.swift
//  StrategyForge
//
//  A rough, honest PRE-RUN cost/token estimate for an arena, so the user sees roughly
//  what a (potentially expensive, minutes-long) run will spend before confirming — not a
//  precise figure, always shown with a "~". Pure, so it's unit-tested.
//
//  Single-provider contestants are estimated as one shot; whole-team contestants reuse the
//  existing CostEstimator (per-role workload × model pricing).
//

import Foundation

enum ArenaCostEstimator {

    struct Estimate: Equatable {
        var tokens: Int
        var usd: Double

        static let zero = Estimate(tokens: 0, usd: 0)

        /// "~24k tok · $0.18" (or just tokens when cost is unknown/zero).
        var headline: String {
            let t = tokens >= 1_000_000 ? String(format: "%.1fM", Double(tokens) / 1_000_000)
                  : tokens >= 1_000 ? "\(tokens / 1_000)k" : "\(tokens)"
            let cost = usd > 0 ? String(format: " · $%.2f", usd) : ""
            return "~\(t) tok\(cost)"
        }
    }

    /// Rough tokens for a prompt (~4 chars/token).
    static func promptTokens(_ prompt: String) -> Int { max(1, prompt.count / 4) }

    /// One single-provider shot. A code shot reads files + writes an edit, so it's much
    /// heavier than a text answer.
    static func shot(prompt: String, model: String, code: Bool) -> Estimate {
        let output = code ? 18_000 : 2_500
        let tokens = promptTokens(prompt) + output
        return Estimate(tokens: tokens, usd: CLIOneShotRunner.estimatedCostUSD(tokens: tokens, model: model))
    }

    /// A whole team's run, via the existing per-role workload estimator.
    static func strategy(_ s: Strategy) -> Estimate {
        let c = CostEstimator.estimate(s)
        return Estimate(tokens: c.perRunTokens, usd: c.perRun)
    }

    static func total(_ parts: [Estimate]) -> Estimate {
        Estimate(tokens: parts.reduce(0) { $0 + $1.tokens }, usd: parts.reduce(0) { $0 + $1.usd })
    }
}
