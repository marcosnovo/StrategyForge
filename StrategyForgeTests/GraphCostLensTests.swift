//
//  GraphCostLensTests.swift
//  StrategyForgeTests
//
//  The node/edge cost lens: model calls per turn (nodes) and avoidable "edge" spend. Pure.
//

import Testing
import Foundation
@testable import Coral

struct GraphCostLensTests {
    private func orch(_ m: ClaudeModel = .opus5) -> AgentRole {
        AgentRole(name: "orchestrator", role: .orchestrator, model: m, systemPrompt: "", description: "", count: 1, isOrchestrator: true)
    }
    private func worker(_ name: String, _ m: ClaudeModel, count: Int) -> AgentRole {
        AgentRole(name: name, role: .worker, model: m, systemPrompt: "", description: "", count: count)
    }

    @Test func countsModelCallsAsNodes() {
        // Orchestrator + 2 researchers (×1) + 1 writer (×1) = plan + 3 + synth = 5 calls.
        let s = Strategy(name: "T", description: "", roles: [orch(),
            worker("researcher", .sonnet5, count: 1), worker("researcher2", .sonnet5, count: 1),
            worker("writer", .haiku45, count: 1)], orchestrationNotes: "")
        #expect(GraphCostLens.analyze(s).modelCalls == 5)
    }

    @Test func flagsSingleWorkerOrchestratorOverhead() {
        let s = Strategy(name: "T", description: "", roles: [orch(), worker("solo", .sonnet5, count: 1)], orchestrationNotes: "")
        let r = GraphCostLens.analyze(s)
        #expect(r.findings.contains { if case .singleWorkerOverhead = $0 { return true } else { return false } })
        #expect(r.estSavingUSD > 0)   // two orchestrator routing calls saved
    }

    @Test func flagsFanoutOnFrontierWithSaving() {
        let s = Strategy(name: "T", description: "", roles: [orch(),
            worker("researcher", .opus5, count: 3), worker("writer", .haiku45, count: 1)], orchestrationNotes: "")
        let r = GraphCostLens.analyze(s)
        let fan = r.findings.first { if case .fanoutOnFrontier = $0 { return true } else { return false } }
        #expect(fan != nil)
        #expect((fan?.savingUSD ?? 0) > 0)   // Opus drones → cheaper tier saves per instance
    }

    @Test func cleanTeamHasNoFindings() {
        // Two distinct cheap workers, no single-worker overhead, no frontier fan-out.
        let s = Strategy(name: "T", description: "", roles: [orch(),
            worker("a", .sonnet5, count: 1), worker("b", .haiku45, count: 1)], orchestrationNotes: "")
        #expect(GraphCostLens.analyze(s).findings.isEmpty)
    }
}
