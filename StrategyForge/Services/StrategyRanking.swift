//
//  StrategyRanking.swift
//  StrategyForge
//
//  How the strategy picker can ORDER its templates: by the dimensions a user actually
//  weighs when picking a team — price, speed, raw intelligence, or value-for-money.
//  Pure + deterministic (grounded in the CostEstimator and the advisor's per-model
//  capability profiles), so the ordering is explainable and unit-testable.
//

import Foundation

/// A way to rank the strategy templates. `.recommended` keeps the library's curated
/// presentation order; the rest sort by a concrete, computed score.
enum StrategyRank: String, CaseIterable, Identifiable {
    case recommended   // the library's own order (a sensible default spread)
    case cheapest      // lowest estimated $ per run
    case fastest       // fast models + small teams → least wall-clock
    case smartest      // the most reasoning power the team brings
    case efficient     // best capability per dollar (value for money)

    var id: String { rawValue }
    var labelKey: String { "picker.sort.\(rawValue)" }
    var icon: String {
        switch self {
        case .recommended: return "sparkles"
        case .cheapest:    return "dollarsign.circle"
        case .fastest:     return "bolt.fill"
        case .smartest:    return "brain.head.profile"
        case .efficient:   return "leaf.fill"
        }
    }
}

enum StrategyRanking {

    /// The advisor's capability profile for a role's (provider, model), if known.
    private static func profile(for role: AgentRole) -> AdvisorEngine.ModelProfile? {
        let id = role.provider == .claude ? role.model.rawValue : (role.providerModelID ?? "")
        return AdvisorEngine.modelProfiles.first { $0.provider == role.provider && $0.modelID == id }
    }

    /// Estimated USD per run (the "cheapest" axis).
    static func cost(_ s: Strategy) -> Double { CostEstimator.estimate(s).perRun }

    /// The peak reasoning capability the team brings (the "smartest" axis).
    static func intelligence(_ s: Strategy) -> Double {
        s.roles.compactMap { profile(for: $0).map { Double($0.reasoning) } }.max() ?? 0
    }

    /// Fast = fast models and a small team. Average model speed, minus a gentle penalty
    /// per agent (more parallel agents means more coordination / more to wait on).
    static func speed(_ s: Strategy) -> Double {
        let speeds = s.roles.compactMap { profile(for: $0).map { Double($0.speed) } }
        let avg = speeds.isEmpty ? 3 : speeds.reduce(0, +) / Double(speeds.count)
        let agents = s.roles.reduce(0) { $0 + max(1, $1.count) }
        return avg - 0.25 * Double(agents)
    }

    /// Value for money: average capability (reasoning + coding) per dollar.
    static func efficiency(_ s: Strategy) -> Double {
        let caps = s.roles.compactMap { profile(for: $0).map { Double($0.reasoning + $0.coding) } }
        let cap = caps.isEmpty ? 4 : caps.reduce(0, +) / Double(caps.count)
        return cap / max(cost(s), 0.01)
    }

    /// Order `strategies` for a rank mode. Deterministic — ties break on the name so the
    /// same input always yields the same order.
    static func sorted(_ strategies: [Strategy], by rank: StrategyRank) -> [Strategy] {
        func by(_ score: (Strategy) -> Double, ascending: Bool) -> [Strategy] {
            strategies.sorted { l, r in
                let a = score(l), b = score(r)
                if a != b { return ascending ? a < b : a > b }
                return l.name < r.name
            }
        }
        switch rank {
        case .recommended: return strategies
        case .cheapest:    return by(cost, ascending: true)
        case .fastest:     return by(speed, ascending: false)
        case .smartest:    return by(intelligence, ascending: false)
        case .efficient:   return by(efficiency, ascending: false)
        }
    }
}
