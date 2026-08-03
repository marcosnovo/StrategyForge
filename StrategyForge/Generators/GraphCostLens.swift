//
//  GraphCostLens.swift
//  StrategyForge
//
//  The NODE/EDGE cost lens: prices a team's generated workflow as the graph it actually is.
//
//  The thesis (from "Graph Engineering with Opus 5"): *the nodes think, the edges carry*.
//  A node is a model call — that's what you pay for. An edge is data moving between nodes,
//  and moving data belongs in code, where it costs nothing. A straight-line chain pays a
//  model to re-read everything upstream at every hop; a real graph carries the same data
//  along `parallel` / `pipeline` / `.join()` and pays once, at synthesis.
//
//  This turns Coral's "no markup" claim into a number the user can see: paid nodes, free
//  edges, how wide the fan-out really is, and what the straight-line version would have
//  cost. It doubles as the standing AUDIT that generated workflows parallelise for real —
//  `parallelWidth == 1` means the "graph" is a line, and a test asserts it never is for a
//  team with teammates.
//
//  Pure and deterministic: it reads the SAME `WorkflowShape` the emitter compiles, and the
//  SAME workload/pricing tables as `CostEstimator`. No I/O, no Date().
//

import Foundation

/// One node in the execution graph — a model call, i.e. a thing you pay for.
struct GraphCostNode: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case plan, scout, work, verify, synthesize

        var labelKey: String { "graphlens.node.\(rawValue)" }
    }

    var id: String { "\(depth)-\(label)" }
    var label: String
    var kind: Kind
    /// The model that runs this node, for the breakdown.
    var model: ClaudeModel
    /// Graph level. Nodes sharing a depth run CONCURRENTLY.
    var depth: Int
    var tokens: Int
    var usd: Double
}

/// What the lens reports for one team.
struct GraphCostReport: Equatable {

    // MARK: Nodes (paid)
    var nodes: [GraphCostNode]
    var paidTokens: Int
    var paidUSD: Double

    // MARK: Edges (free)
    /// How many edges carry data between nodes.
    var edgeCount: Int
    /// Tokens those edges move — carried by code, billed at zero.
    var edgeTokens: Int

    // MARK: The comparison that makes it mean something
    /// What the same work would cost as one sequential chain, where every hop re-reads all
    /// the upstream results through the model instead of through code.
    var straightLineTokens: Int
    var straightLineUSD: Double

    // MARK: Shape
    /// Widest concurrent step. 1 means the graph is a straight line.
    var parallelWidth: Int
    /// Number of sequential levels — the wall-clock depth.
    var criticalPath: Int

    /// A graph is only a graph if something actually runs in parallel.
    var isParallel: Bool { parallelWidth > 1 }

    var savedTokens: Int { max(0, straightLineTokens - paidTokens) }
    var savedUSD: Double { max(0, straightLineUSD - paidUSD) }
    /// Share of the straight-line spend the graph avoids, 0…1.
    var savedFraction: Double {
        straightLineUSD > 0 ? min(1, savedUSD / straightLineUSD) : 0
    }

    /// "−41%" — empty when there's nothing to save (a two-node graph has no re-reads).
    var savedPercentShort: String {
        savedFraction >= 0.005 ? "−\(Int((savedFraction * 100).rounded()))%" : ""
    }

    static func compact(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return "\(tokens / 1_000)k" }
        return "\(tokens)"
    }

    var paidShort: String { "~\(Self.compact(paidTokens)) · " + String(format: "$%.2f", paidUSD) }
    var edgeShort: String { "~\(Self.compact(edgeTokens)) · $0.00" }
}

enum GraphCostLens {

    /// The fan-out width a scouted item pipeline is priced at when the team doesn't say.
    /// The emitted scout prompt caps itself at 50 items; pricing 50 agents for a team that
    /// asked for 3 would be alarmist, so the role's own instance count is the estimate.
    static let maxScoutedItems = 50

    /// Price a team's workflow as a graph, or nil for a team that doesn't compile to one
    /// (a solo agent is a prompt, not a graph).
    static func report(for strategy: Strategy, effort: CostEffort = .medium) -> GraphCostReport? {
        guard let shape = WorkflowGenerator.shape(for: strategy) else { return nil }
        return report(for: shape, effort: effort)
    }

    static func report(for shape: WorkflowShape, effort: CostEffort = .medium) -> GraphCostReport {
        let m = effort.multiplier

        /// One priced node from a role, at a graph depth.
        func node(_ role: AgentRole, kind: GraphCostNode.Kind, label: String, depth: Int,
                  scale: Double = 1) -> GraphCostNode {
            // Every node here delegates to nobody: it does its own slice of work. The
            // orchestrator's PLAN and SYNTHESIZE nodes are the light, delegating kind.
            let delegating = (kind == .plan || kind == .scout || kind == .synthesize)
            let load = CostEstimator.workload(isOrchestrator: role.isOrchestrator,
                                              role: role.role,
                                              canDelegate: delegating)
            let input = load.input * m * scale
            let output = load.output * m * scale
            return GraphCostNode(label: label, kind: kind, model: role.model, depth: depth,
                                 tokens: Int(input + output),
                                 usd: CostEstimator.callCostUSD(input: input, output: output,
                                                                model: role.model))
        }

        var nodes: [GraphCostNode] = []
        let orchestrator: AgentRole
        let verifier: AgentRole?

        switch shape {
        case let .roleParallel(lead, workers, v):
            orchestrator = lead
            verifier = v
            nodes.append(node(lead, kind: .plan, label: "plan", depth: 0))
            for w in workers {
                // A role with count > 1 becomes that many concurrent branches.
                for i in 0..<max(1, w.count) {
                    let label = w.count > 1 ? "\(w.name)-\(i + 1)" : w.name
                    nodes.append(node(w, kind: .work, label: label, depth: 1))
                }
            }
            if let v {
                // One verify node per produced result — the emitter maps over `results`.
                let produced = nodes.filter { $0.kind == .work }.count
                for i in 0..<produced {
                    nodes.append(node(v, kind: .verify, label: "verify:\(i)", depth: 2))
                }
            }
            nodes.append(node(lead, kind: .synthesize, label: "synthesize",
                              depth: verifier == nil ? 2 : 3))

        case let .itemFanout(lead, worker, v, instances):
            orchestrator = lead
            verifier = v
            let items = min(max(1, instances), maxScoutedItems)
            nodes.append(node(lead, kind: .scout, label: "scout", depth: 0))
            for i in 0..<items {
                // A per-ITEM agent handles one slice, not the whole task — a fraction of a
                // full role workload. Scaling by the fan-out width keeps the total honest:
                // splitting the job across more agents doesn't multiply the job.
                nodes.append(node(worker, kind: .work, label: "work:\(i + 1)", depth: 1,
                                  scale: itemScale(items)))
            }
            if let v {
                for i in 0..<items {
                    nodes.append(node(v, kind: .verify, label: "verify:\(i + 1)", depth: 2,
                                      scale: itemScale(items)))
                }
            }
            nodes.append(node(lead, kind: .synthesize, label: "synthesize",
                              depth: verifier == nil ? 2 : 3))
        }

        // ── Edges. Every node but the roots is fed by exactly one upstream node, and every
        // non-terminal node feeds synthesis — the shape the emitter writes as
        // `parallel(...)` / `pipeline(...)` + `.filter(Boolean).join()`. All of it is code.
        let works = nodes.filter { $0.kind == .work }
        let verifies = nodes.filter { $0.kind == .verify }
        let edgeCount = works.count                       // plan/scout → each worker
            + verifies.count                              // worker → its verifier
            + (verifies.isEmpty ? works.count : verifies.count)  // → synthesize

        // What those edges carry: the producing node's result, once per edge.
        let rootOutput = nodes.first?.tokens ?? 0
        let carriedByRoot = works.count * rootOutput / 2   // the plan is mostly input; halve it
        let carriedByWork = works.reduce(0) { $0 + $1.tokens / 2 }
        let carriedByVerify = verifies.reduce(0) { $0 + $1.tokens / 2 }
        let edgeTokens = carriedByRoot + carriedByWork + carriedByVerify

        // ── The straight-line baseline. Same nodes, run as one chain: node i additionally
        // re-reads every earlier node's result THROUGH THE MODEL. That re-read is the tax
        // the graph doesn't pay, because code carried it instead.
        var reReadTokens = 0.0
        var upstream = 0.0
        for n in nodes {
            reReadTokens += upstream
            upstream += Double(n.tokens) / 2     // roughly the half of a node that is output
        }
        let paidTokens = nodes.reduce(0) { $0 + $1.tokens }
        let paidUSD = nodes.reduce(0.0) { $0 + $1.usd }
        // Re-reads are fresh input on the lead's model — no cache discount applies to a
        // payload that changes every hop.
        let reReadUSD = reReadTokens / 1_000_000 * CostEstimator.freshInputPerMillion(orchestrator.model)

        let depths = Set(nodes.map(\.depth))
        let width = depths.map { d in nodes.filter { $0.depth == d }.count }.max() ?? 1

        return GraphCostReport(
            nodes: nodes,
            paidTokens: paidTokens,
            paidUSD: paidUSD,
            edgeCount: edgeCount,
            edgeTokens: edgeTokens,
            straightLineTokens: paidTokens + Int(reReadTokens),
            straightLineUSD: paidUSD + reReadUSD,
            parallelWidth: max(1, width),
            criticalPath: max(1, depths.count))
    }

    /// How much of a full role workload ONE item-agent carries. The work is divided, not
    /// duplicated, but each agent still pays a fixed cost to orient itself — so the total
    /// grows sub-linearly rather than staying flat.
    private static func itemScale(_ items: Int) -> Double {
        guard items > 1 else { return 1 }
        return 0.35 + 0.65 / Double(items)
    }
}
