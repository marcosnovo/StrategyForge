//
//  ArenaCostEstimatorTests.swift
//  StrategyForgeTests
//
//  The rough pre-run estimate: a code shot costs more than a text shot, a whole team
//  costs more than a single shot, and totals sum across contestants.
//

import Testing
import Foundation
@testable import Coral

struct ArenaCostEstimatorTests {

    @Test func codeShotIsHeavierThanTextShot() {
        let text = ArenaCostEstimator.shot(prompt: "do the thing", model: "claude-opus-4-8", code: false)
        let code = ArenaCostEstimator.shot(prompt: "do the thing", model: "claude-opus-4-8", code: true)
        #expect(code.tokens > text.tokens)
        #expect(code.usd >= text.usd)
    }

    @Test func aTeamCostsMoreThanASingleShot() {
        let team = ArenaCostEstimator.strategy(StrategyLibrary.orchestratorWorkers())
        let shot = ArenaCostEstimator.shot(prompt: "x", model: "claude-opus-4-8", code: false)
        #expect(team.tokens > shot.tokens)
    }

    @Test func totalSumsContestants() {
        let a = ArenaCostEstimator.Estimate(tokens: 100, usd: 0.10)
        let b = ArenaCostEstimator.Estimate(tokens: 250, usd: 0.25)
        let total = ArenaCostEstimator.total([a, b])
        #expect(total.tokens == 350)
        #expect(abs(total.usd - 0.35) < 1e-9)
        #expect(ArenaCostEstimator.total([]) == .zero)
    }

    @Test func headlineFormatsTokensAndCost() {
        #expect(ArenaCostEstimator.Estimate(tokens: 24_000, usd: 0.18).headline == "~24k tok · $0.18")
        #expect(ArenaCostEstimator.Estimate(tokens: 500, usd: 0).headline == "~500 tok")
    }
}
