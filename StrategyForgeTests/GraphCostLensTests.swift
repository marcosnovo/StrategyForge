//
//  GraphCostLensTests.swift
//  StrategyForgeTests
//
//  Two things at once:
//
//  1. The node/edge cost lens itself — paid nodes vs free edges, the straight-line
//     comparison, the shape metrics, and that it stays pure/deterministic.
//  2. The standing PARALLELISM AUDIT. The competitive analysis asked us to verify that
//     generated workflows fan out for real instead of being straight lines with extra
//     ceremony. String-matching the emitted JavaScript proves the text; asserting on the
//     shared `WorkflowShape` proves the GRAPH — and it keeps proving it for every template
//     anyone adds later, because the sweep is over `StrategyLibrary.all`.
//

import Testing
import Foundation
@testable import Coral

struct GraphCostLensTests {

    // MARK: - The audit

    /// How many agents the team says should be doing the work — reviewers gate the edge
    /// rather than produce, so they aren't part of the fan-out.
    private func producerInstances(_ s: Strategy) -> Int {
        let producers = s.subagentRoles.filter { $0.role != .reviewer }
        let effective = producers.isEmpty ? s.subagentRoles : producers
        return effective.reduce(0) { $0 + max(1, $1.count) }
    }

    @Test func theGraphIsExactlyAsWideAsTheTeamAllows() {
        // THE AUDIT. Not "is it parallel?" (a one-teammate team honestly isn't) but the
        // stronger claim: the emitted graph never runs NARROWER than the roster. A role
        // with count: 3 that quietly became one branch is a straight line in costume.
        for strategy in StrategyLibrary.all where !strategy.subagentRoles.isEmpty {
            guard let report = GraphCostLens.report(for: strategy) else {
                Issue.record("\(strategy.name) has teammates but compiles to no graph")
                continue
            }
            let expected = min(producerInstances(strategy), GraphCostLens.maxScoutedItems)
            #expect(report.parallelWidth == expected,
                    "\(strategy.name): \(expected) producers but width \(report.parallelWidth)")
            #expect(report.isParallel == (expected >= 2), "\(strategy.name) fan-out mismatch")
            // Plan/scout → work → synthesize is the minimum; a verifier adds a fourth level.
            #expect(report.criticalPath >= 3, "\(strategy.name) has no distinct phases")
        }
    }

    @Test func theEmittedWorkflowFansOutAsWideAsTheLensSays() {
        // The same audit against the JavaScript that actually ships in the repo: one
        // labelled Work branch per producer instance.
        for strategy in StrategyLibrary.all where !strategy.subagentRoles.isEmpty {
            guard case .roleParallel = WorkflowGenerator.shape(for: strategy),
                  let js = WorkflowGenerator.workflow(for: strategy) else { continue }
            let branches = js.components(separatedBy: "phase: 'Work'").count - 1
            #expect(branches == producerInstances(strategy),
                    "\(strategy.name): \(branches) branches for \(producerInstances(strategy)) producers")
        }
    }

    @Test func theShapeTheLensPricesIsTheShapeTheEmitterWrites() {
        for strategy in StrategyLibrary.all where !strategy.subagentRoles.isEmpty {
            guard let shape = WorkflowGenerator.shape(for: strategy),
                  let js = WorkflowGenerator.workflow(for: strategy) else {
                Issue.record("\(strategy.name): shape and workflow disagree about existing")
                continue
            }
            switch shape {
            case .roleParallel:
                #expect(js.contains("phase('Plan')"))
                #expect(js.contains("await parallel(["))
                #expect(!js.contains("phase('Scout')"))
            case .itemFanout:
                #expect(js.contains("phase('Scout')"))
                #expect(js.contains("items"))
            }
            // A Verify phase appears exactly when the shape carries a verifier. (The
            // meta block is the shape-independent place to look: the item fan-out runs
            // verification inside its pipeline rather than as a `phase('Verify')` call.)
            #expect(js.contains("{ title: 'Verify' }") == (shape.verifier != nil))
        }
    }

    @Test func aSoloTeamIsAPromptNotAGraph() {
        #expect(GraphCostLens.report(for: StrategyLibrary.solo()) == nil)
        #expect(GraphCostLens.report(for: StrategyLibrary.soloEconomy()) == nil)
        #expect(WorkflowGenerator.shape(for: StrategyLibrary.solo()) == nil)
    }

    // MARK: - Nodes are paid

    @Test func everyNodeIsPricedAndTheyAddUp() {
        let report = GraphCostLens.report(for: StrategyLibrary.domainSpecialists())!
        #expect(!report.nodes.isEmpty)
        #expect(report.nodes.allSatisfy { $0.tokens > 0 })
        #expect(report.paidTokens == report.nodes.reduce(0) { $0 + $1.tokens })
        #expect(abs(report.paidUSD - report.nodes.reduce(0.0) { $0 + $1.usd }) < 0.0001)
        #expect(report.paidUSD > 0)
    }

    @Test func theGraphHasExactlyOnePlanAndOneSynthesisNode() {
        let report = GraphCostLens.report(for: StrategyLibrary.domainSpecialists())!
        #expect(report.nodes.filter { $0.kind == .plan }.count == 1)
        #expect(report.nodes.filter { $0.kind == .synthesize }.count == 1)
        // One Work node per producer instance; the reviewer is NOT one of them.
        let producers = StrategyLibrary.domainSpecialists().subagentRoles
            .filter { $0.role != .reviewer }
            .reduce(0) { $0 + max(1, $1.count) }
        #expect(report.nodes.filter { $0.kind == .work }.count == producers)
    }

    @Test func aRoleWithCountGreaterThanOneBecomesThatManyConcurrentNodes() {
        var s = StrategyLibrary.executorAdvisor()          // role-parallel, no fan-out
        guard let i = s.roles.firstIndex(where: { !$0.isOrchestrator }) else { return }
        let before = GraphCostLens.report(for: s)!.parallelWidth
        s.roles[i].count = s.roles[i].count + 2
        let after = GraphCostLens.report(for: s)!
        #expect(after.parallelWidth == before + 2)
        #expect(after.paidUSD > 0)
    }

    // MARK: - Edges are free

    @Test func edgesCarryDataAndCostNothing() {
        let report = GraphCostLens.report(for: StrategyLibrary.domainSpecialists())!
        #expect(report.edgeCount > 0)
        #expect(report.edgeTokens > 0)                     // they move real payload…
        #expect(report.edgeShort.hasSuffix("$0.00"))       // …and it is billed at zero
        // Every non-root node is fed, and every producing node feeds synthesis.
        #expect(report.edgeCount >= report.nodes.count - 1)
    }

    // MARK: - The comparison that gives it meaning

    @Test func theStraightLineVersionCostsMore() {
        let report = GraphCostLens.report(for: StrategyLibrary.domainSpecialists())!
        #expect(report.straightLineTokens > report.paidTokens)
        #expect(report.straightLineUSD > report.paidUSD)
        #expect(report.savedUSD > 0)
        #expect(report.savedFraction > 0 && report.savedFraction <= 1)
        #expect(report.savedPercentShort.hasPrefix("−"))
    }

    @Test func aWiderTeamSavesMoreThanANarrowOne() {
        // More nodes in a chain means more re-reading, so the graph avoids more.
        let narrow = GraphCostLens.report(for: StrategyLibrary.executorAdvisor())!
        let wide = GraphCostLens.report(for: StrategyLibrary.domainSpecialists())!
        #expect(wide.savedUSD > narrow.savedUSD)
    }

    @Test func savedPercentIsBlankWhenThereIsNothingToSave() {
        let empty = GraphCostReport(nodes: [], paidTokens: 100, paidUSD: 1,
                                    edgeCount: 0, edgeTokens: 0,
                                    straightLineTokens: 100, straightLineUSD: 1,
                                    parallelWidth: 1, criticalPath: 1)
        #expect(empty.savedPercentShort.isEmpty)
        #expect(!empty.isParallel)
        #expect(empty.savedUSD == 0)
    }

    // MARK: - Shape metrics

    @Test func aVerifierAddsALevelToTheCriticalPath() {
        var s = StrategyLibrary.domainSpecialists()
        let withVerifier = GraphCostLens.report(for: s)!
        s.roles.removeAll { $0.role == .reviewer }
        let without = GraphCostLens.report(for: s)!
        #expect(withVerifier.criticalPath == without.criticalPath + 1)
        #expect(withVerifier.nodes.contains { $0.kind == .verify })
        #expect(!without.nodes.contains { $0.kind == .verify })
    }

    @Test func higherEffortScalesEveryNode() {
        let low = GraphCostLens.report(for: StrategyLibrary.domainSpecialists(), effort: .low)!
        let high = GraphCostLens.report(for: StrategyLibrary.domainSpecialists(), effort: .high)!
        #expect(high.paidTokens > low.paidTokens)
        #expect(high.paidUSD > low.paidUSD)
        // Effort changes the price, never the shape.
        #expect(high.parallelWidth == low.parallelWidth)
        #expect(high.criticalPath == low.criticalPath)
        #expect(high.nodes.count == low.nodes.count)
    }

    @Test func itemFanoutDividesTheWorkInsteadOfDuplicatingIt() {
        // A migration fans one agent out per file. Ten agents must not cost ten full
        // role workloads — the job is split, not repeated.
        let s = StrategyLibrary.languageMigration()
        guard case let .itemFanout(_, _, _, instances) = WorkflowGenerator.shape(for: s)! else {
            Issue.record("languageMigration should compile to an item fan-out")
            return
        }
        let report = GraphCostLens.report(for: s)!
        let workNodes = report.nodes.filter { $0.kind == .work }
        #expect(workNodes.count > 1)
        #expect(workNodes.count == min(instances, GraphCostLens.maxScoutedItems))

        // A whole worker's load, from the one table both estimators read.
        let full = CostEstimator.workload(isOrchestrator: false, role: .worker, canDelegate: false)
        let fullTokens = Int(full.input + full.output)
        let totalWork = workNodes.reduce(0) { $0 + $1.tokens }
        // More than one agent's worth of work (fanning out isn't free) …
        #expect(totalWork > fullTokens)
        // … but nowhere near N full workloads: the job is divided, not repeated.
        #expect(totalWork < workNodes.count * fullTokens)
        #expect(workNodes.allSatisfy { $0.tokens < fullTokens })
    }

    @Test func theLensIsPureAndDeterministic() {
        let a = GraphCostLens.report(for: StrategyLibrary.plannerImplementersReviewer())!
        let b = GraphCostLens.report(for: StrategyLibrary.plannerImplementersReviewer())!
        #expect(a == b)
    }
}
