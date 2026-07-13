//
//  RunAnalysis.swift
//  StrategyForge
//
//  Turns a finished run (a persisted `TurnActivity`) into something actionable —
//  the piece that makes Coral a test-bench for teams, not just a generator:
//
//   • retune(turn:strategy:) reads a single run's outcome and suggests concrete
//     changes to the team (an agent that never contributed, one model hogging the
//     cost, a team that never actually delegated, an expensive run).
//   • compare(_:_:strategy:) diffs two runs of the same team so an A/B of two
//     topologies is legible (cost, tokens, steps, time, and per-agent deltas).
//
//  Pure and deterministic (same inputs → same output), so the "why" is explainable
//  and every heuristic is unit-tested without spawning anything.
//

import Foundation

enum RunAnalysis {

    // MARK: - Re-tune suggestions

    /// The class of a suggestion — drives the icon/severity in the UI.
    enum RetuneKind: String, Hashable {
        case idleAgent        // a role in the team did no work this run
        case costHog          // one model dominated the token spend
        case noDelegation     // the orchestrator did everything; the team never split
        case expensiveRun     // the run cost more than a routine-work threshold
    }

    enum Severity: Int, Hashable { case info = 0, suggestion = 1, warning = 2 }

    /// One actionable observation about a run. `subject`/`value` fill a localized
    /// template (e.g. "{subject} used {value} of the tokens…").
    struct RetuneSuggestion: Identifiable, Hashable {
        let id: String
        let kind: RetuneKind
        let severity: Severity
        let messageKey: String
        let subject: String
        let value: String
    }

    /// A run costs more than this (USD) → nudge toward a cheaper tier for routine work.
    static let expensiveRunUSD = 1.0
    /// A single model taking more than this share of tokens is a cost hog.
    static let costHogShare = 0.6

    /// Analyze one finished run against the team that produced it. Ordered by
    /// severity (most important first), then kind, for a stable UI.
    static func retune(turn: TurnActivity, strategy: Strategy) -> [RetuneSuggestion] {
        var out: [RetuneSuggestion] = []
        let subagents = strategy.subagentRoles

        // 1) Idle agents — a role that never showed up in this run's attribution.
        //    (Only meaningful for teams that HAVE subagents.)
        if !subagents.isEmpty {
            for role in subagents where !contributed(role.name, in: turn) {
                out.append(RetuneSuggestion(
                    id: "idle:\(role.name)", kind: .idleAgent, severity: .suggestion,
                    messageKey: "retune.idleAgent", subject: role.name, value: ""))
            }
        }

        // 2) No delegation — a team with subagents where nothing was delegated and no
        //    subagent was attributed any step. The orchestrator did it all solo.
        if !subagents.isEmpty,
           turn.agentsInvolved.isEmpty,
           !turn.steps.contains(where: { $0.isDelegation }),
           !turn.steps.isEmpty {
            out.append(RetuneSuggestion(
                id: "noDelegation", kind: .noDelegation, severity: .warning,
                messageKey: "retune.noDelegation", subject: "", value: ""))
        }

        // 3) Cost hog — one model with a dominant token share while others exist.
        let totalModelTokens = turn.byModel.reduce(0) { $0 + $1.tokens }
        if turn.byModel.count >= 2, totalModelTokens > 0,
           let top = turn.byModel.max(by: { $0.tokens < $1.tokens }) {
            let share = Double(top.tokens) / Double(totalModelTokens)
            if share >= costHogShare {
                out.append(RetuneSuggestion(
                    id: "costHog:\(top.model)", kind: .costHog, severity: .suggestion,
                    messageKey: "retune.costHog",
                    subject: friendlyModel(top.model),
                    value: "\(Int((share * 100).rounded()))%"))
            }
        }

        // 4) Expensive run — over the routine-work threshold.
        if turn.costUSD >= expensiveRunUSD {
            out.append(RetuneSuggestion(
                id: "expensive", kind: .expensiveRun, severity: .info,
                messageKey: "retune.expensiveRun", subject: "",
                value: String(format: "$%.2f", turn.costUSD)))
        }

        return out.sorted {
            $0.severity.rawValue != $1.severity.rawValue
                ? $0.severity.rawValue > $1.severity.rawValue
                : $0.id < $1.id
        }
    }

    /// Whether a role did any attributable work this run (loose name match against
    /// the per-agent token map and the involved-agents list).
    private static func contributed(_ roleName: String, in turn: TurnActivity) -> Bool {
        if turn.agentsInvolved.contains(where: { StrategyDiagramView.titlesMatch($0, roleName) }) {
            return true
        }
        return turn.byAgent.contains { key, tokens in
            tokens > 0 && StrategyDiagramView.titlesMatch(key, roleName)
        }
    }

    // MARK: - Compare two runs

    /// Per-agent side-by-side for two runs (tokens + steps).
    struct AgentDelta: Hashable, Identifiable {
        var id: String { name }
        let name: String
        let tokensA: Int
        let tokensB: Int
        let stepsA: Int
        let stepsB: Int
    }

    /// The full diff of two runs of the same team.
    struct RunDelta: Hashable {
        let costA: Double, costB: Double
        let tokensA: Int, tokensB: Int
        let stepsA: Int, stepsB: Int
        let secondsA: Double, secondsB: Double
        let agents: [AgentDelta]

        var costDelta: Double { costB - costA }
        var tokenDelta: Int { tokensB - tokensA }
        var stepDelta: Int { stepsB - stepsA }
        var secondsDelta: Double { secondsB - secondsA }

        /// Signed percent change in cost (B vs A); nil when A had no cost to compare.
        var costPercent: Double? {
            costA > 0 ? (costB - costA) / costA * 100 : nil
        }
    }

    /// Diff run `a` (baseline) against run `b` (candidate). The agent list is the
    /// union of both runs' attributed agents, sorted by combined tokens desc then name.
    static func compare(_ a: TurnActivity, _ b: TurnActivity, strategy: Strategy) -> RunDelta {
        let names = Set(a.byAgent.keys).union(b.byAgent.keys)
            .union(stepAgents(a)).union(stepAgents(b))
        let agents = names.map { name in
            AgentDelta(name: name,
                       tokensA: a.byAgent[name] ?? 0,
                       tokensB: b.byAgent[name] ?? 0,
                       stepsA: stepCount(a, agent: name),
                       stepsB: stepCount(b, agent: name))
        }.sorted {
            let ta = $0.tokensA + $0.tokensB, tb = $1.tokensA + $1.tokensB
            return ta != tb ? ta > tb : $0.name < $1.name
        }
        return RunDelta(
            costA: a.costUSD, costB: b.costUSD,
            tokensA: a.tokensUsed, tokensB: b.tokensUsed,
            stepsA: a.steps.count, stepsB: b.steps.count,
            secondsA: max(0, a.endedAt.timeIntervalSince(a.startedAt)),
            secondsB: max(0, b.endedAt.timeIntervalSince(b.startedAt)),
            agents: agents)
    }

    private static func stepAgents(_ turn: TurnActivity) -> Set<String> {
        Set(turn.steps.compactMap { $0.agent })
    }

    private static func stepCount(_ turn: TurnActivity, agent: String) -> Int {
        turn.steps.filter { ($0.agent ?? "") == agent }.count
    }

    // MARK: - Helpers

    /// A friendly display name for a raw model id (Claude ids resolve; others pass
    /// through, already being human-ish provider model ids).
    static func friendlyModel(_ id: String) -> String {
        ClaudeModel(rawValue: id)?.displayName ?? id
    }
}
