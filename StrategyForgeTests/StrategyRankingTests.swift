//
//  StrategyRankingTests.swift
//  StrategyForgeTests
//
//  Unit tests for the picker's sort/rank engine: each mode orders the library by its
//  score, "Recommended" preserves the curated order, and sorting is deterministic.
//

import Testing
import Foundation
@testable import Coral

struct StrategyRankingTests {

    private var all: [Strategy] { StrategyLibrary.all }

    @Test func recommendedKeepsTheLibraryOrder() {
        #expect(StrategyRanking.sorted(all, by: .recommended).map(\.name) == all.map(\.name))
    }

    @Test func cheapestIsNonDecreasingByCost() {
        let costs = StrategyRanking.sorted(all, by: .cheapest).map { StrategyRanking.cost($0) }
        #expect(costs == costs.sorted())
    }

    @Test func smartestIsNonIncreasingByIntelligence() {
        let vals = StrategyRanking.sorted(all, by: .smartest).map { StrategyRanking.intelligence($0) }
        #expect(vals == vals.sorted(by: >))
    }

    @Test func fastestIsNonIncreasingBySpeed() {
        let vals = StrategyRanking.sorted(all, by: .fastest).map { StrategyRanking.speed($0) }
        #expect(vals == vals.sorted(by: >))
    }

    @Test func efficientIsNonIncreasingByValue() {
        let vals = StrategyRanking.sorted(all, by: .efficient).map { StrategyRanking.efficiency($0) }
        #expect(vals == vals.sorted(by: >))
    }

    @Test func cheapestPutsSoloBeforeABigFanout() {
        // The first card under "Cheapest" really is the lowest-cost template. (Note: a
        // lone agent on a top model doing everything can cost MORE than a fan-out of
        // cheap workers, so we assert the min directly rather than assuming solo wins.)
        let ordered = StrategyRanking.sorted(all, by: .cheapest)
        let minCost = all.map { StrategyRanking.cost($0) }.min()!
        #expect(abs(StrategyRanking.cost(ordered.first!) - minCost) < 1e-9)
    }

    @Test func sortingIsDeterministic() {
        for rank in StrategyRank.allCases {
            let a = StrategyRanking.sorted(all, by: rank).map(\.name)
            let b = StrategyRanking.sorted(all, by: rank).map(\.name)
            #expect(a == b, "\(rank) not deterministic")
        }
    }
}
