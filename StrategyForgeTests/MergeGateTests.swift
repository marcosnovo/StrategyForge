//
//  MergeGateTests.swift
//  StrategyForgeTests
//
//  The Eval-Engineering merge gate: evidence is read in a fixed order, decisions follow
//  blast-radius lanes, and self-assessment can only ever downgrade — never open — a lane.
//

import Testing
import Foundation
@testable import Coral

struct MergeGateTests {

    private func blast(_ r: BlastRadius, files: Int = 1) -> BlastAssessment {
        BlastAssessment(radius: r, reasons: [r.rawValue], filesChanged: files)
    }

    @Test func irreversibleIsAlwaysBlockedRegardlessOfEvidence() {
        let e = MergeEvidence(blast: blast(.irreversible), deterministicPassed: true,
                              blockingFindings: 0, trajectoryClean: true, selfAssessment: 1.0)
        #expect(MergeGate.evaluate(e).decision == .blocked)
    }

    @Test func containedWithPassingChecksAutoMerges() {
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: true)
        #expect(MergeGate.evaluate(e).decision == .autoMerge)
    }

    @Test func failingDeterministicChecksBlock() {
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: false)
        let v = MergeGate.evaluate(e)
        #expect(v.decision == .blocked)
        #expect(v.decidingTier == "deterministic")
    }

    @Test func missingChecksDoNotCountAsAPass() {
        // Contained but no deterministic run → can't auto-merge.
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: nil)
        #expect(MergeGate.evaluate(e).decision == .needsReview)
    }

    @Test func blockingFindingsForceReview() {
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: true, blockingFindings: 1)
        let v = MergeGate.evaluate(e)
        #expect(v.decision == .needsReview)
        #expect(v.decidingTier == "review")
    }

    @Test func wideNeedsCleanTrajectoryToAutoMerge() {
        let dirty = MergeEvidence(blast: blast(.wide, files: 12), deterministicPassed: true, trajectoryClean: false)
        #expect(MergeGate.evaluate(dirty).decision == .needsReview)
        let clean = MergeEvidence(blast: blast(.wide, files: 12), deterministicPassed: true, trajectoryClean: true)
        #expect(MergeGate.evaluate(clean).decision == .autoMerge)
    }

    @Test func repeatedRollbacksNeedAHuman() {
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: true,
                              priorRollbacks: MergeGate.rollbackReviewThreshold)
        let v = MergeGate.evaluate(e)
        #expect(v.decision == .needsReview)
        #expect(v.decidingTier == "history")
    }

    @Test func lowSelfAssessmentOnlyDowngrades() {
        // Low confidence downgrades an otherwise-auto lane…
        let auto = MergeEvidence(blast: blast(.contained), deterministicPassed: true, selfAssessment: 0.2)
        #expect(MergeGate.evaluate(auto).decision == .needsReview)
        // …but high confidence can NOT open a lane that deterministic checks didn't clear.
        let noChecks = MergeEvidence(blast: blast(.contained), deterministicPassed: nil, selfAssessment: 1.0)
        #expect(MergeGate.evaluate(noChecks).decision == .needsReview)
    }

    @Test func shadowModeNeverAutoMerges() {
        let e = MergeEvidence(blast: blast(.contained), deterministicPassed: true)
        #expect(MergeGate.evaluate(e, shadow: false).decision == .autoMerge)
        let shadow = MergeGate.evaluate(e, shadow: true)
        #expect(shadow.decision == .needsReview)
        #expect(shadow.decidingTier == "shadow")
    }
}
