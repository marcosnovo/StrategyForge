//
//  GraphCostLens.swift
//  StrategyForge
//
//  "The nodes think, the edges transport — and a brutal amount of what people pay in tokens is
//  actually an edge, and edges are free." (Graph Engineering con Opus 5, 2026). This lens reads
//  a team's topology and separates spend that BUYS THINKING (model calls = nodes) from spend
//  that's really routing/merging/fan-out overhead (edges) which can be cut with a cheaper model,
//  fewer clones, or plain code. Pure + tested; the UI turns it into an at-a-glance card.
//

import Foundation

enum GraphCostLens {

    /// One avoidable ("edge") cost the lens found, with an estimated per-turn saving in USD.
    enum Finding: Equatable, Sendable, Identifiable {
        /// Orchestrator plan+synthesize just to route to a SINGLE worker — two extra model
        /// calls that a Solo/Executor shape would skip.
        case singleWorkerOverhead(savingUSD: Double)
        /// Parallel clones of a role running on a frontier (expensive) model — drones rarely
        /// need the top tier; a cheaper one saves per instance.
        case fanoutOnFrontier(role: String, instances: Int, savingUSD: Double)
        /// A role fanned out to a lot of instances — likely more parallelism than the task needs.
        case excessiveFanout(role: String, count: Int)

        var id: String {
            switch self {
            case .singleWorkerOverhead: return "singleWorker"
            case .fanoutOnFrontier(let r, _, _): return "fanout:\(r)"
            case .excessiveFanout(let r, _): return "excess:\(r)"
            }
        }
        var savingUSD: Double {
            switch self {
            case .singleWorkerOverhead(let s): return s
            case .fanoutOnFrontier(_, _, let s): return s
            case .excessiveFanout: return 0
            }
        }
    }

    struct Report: Sendable, Equatable {
        var modelCalls: Int         // "nodes" — the model calls this team makes per turn
        var findings: [Finding]
        var estSavingUSD: Double    // sum of the findings' per-turn savings
        var hasSavings: Bool { estSavingUSD > 0 || !findings.isEmpty }
    }

    /// Rough tokens one model call costs (blended in+out) — an estimate, always shown with a "~".
    static let assumedTokensPerCall = 8_000.0
    static let excessiveFanoutThreshold = 4

    private static func perCallUSD(_ model: ClaudeModel) -> Double {
        guard let p = Constants.pricing[model.rawValue] else { return 0 }
        return assumedTokensPerCall / 1_000_000 * (p.inputPerM + p.outputPerM) / 2
    }

    /// Frontier (expensive) tiers where a parallel drone is usually overkill.
    private static func isFrontier(_ m: ClaudeModel) -> Bool { m == .opus5 || m == .opus48 || m == .fable5 }
    /// The cheaper model a fan-out drone could use instead (keeps the same provider family).
    private static let droneModel: ClaudeModel = .sonnet5

    static func analyze(_ strategy: Strategy) -> Report {
        let workers = strategy.subagentRoles
        let orch = strategy.orchestrator

        // Nodes = model calls per turn: plan + one per worker instance + synthesize (team); or 1 (solo).
        let workerInstances = workers.reduce(0) { $0 + max(1, $1.count) }
        let modelCalls = workers.isEmpty ? 1 : (2 + workerInstances)

        var findings: [Finding] = []

        // Single-worker overhead: the orchestrator's plan + synthesize are pure routing to ONE
        // agent — two "edge" calls a Solo/Executor shape wouldn't pay.
        if workers.count == 1, (workers.first?.count ?? 1) <= 1, let orch {
            let saving = 2 * perCallUSD(orch.model)
            if saving > 0 { findings.append(.singleWorkerOverhead(savingUSD: saving)) }
        }

        for role in workers {
            let instances = max(1, role.count)
            // Fan-out on a frontier model → the extra instances are edge overhead priced at the
            // top tier; a cheaper drone model saves the difference per instance.
            if instances >= 2, isFrontier(role.model) {
                let per = perCallUSD(role.model) - perCallUSD(droneModel)
                let saving = max(0, per) * Double(instances)
                if saving > 0 {
                    findings.append(.fanoutOnFrontier(role: role.name, instances: instances, savingUSD: saving))
                }
            }
            if instances > excessiveFanoutThreshold {
                findings.append(.excessiveFanout(role: role.name, count: instances))
            }
        }

        let total = findings.reduce(0) { $0 + $1.savingUSD }
        return Report(modelCalls: modelCalls, findings: findings, estSavingUSD: total)
    }
}
