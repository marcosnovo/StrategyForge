//
//  AdvisorEngineTests.swift
//  StrategyForgeTests
//
//  Unit tests for the Advisor decision tree: model routing (EN + ES), loop-kind
//  detection, the cheap-model team downgrade, decision-path shape, and
//  determinism. The engine is pure, so no mocks are needed.
//

import Testing
import Foundation
@testable import Coral

struct AdvisorEngineTests {

    // MARK: - Model routing

    @Test func shortSpanishSummaryGetsHaikuAndTurnBased() {
        let advice = AdvisorEngine.advise(task: "Resume este párrafo en dos líneas")
        #expect(advice.model == .haiku45)
        #expect(advice.loopKind == .turnBased)
        #expect(advice.effort == .low)
    }

    @Test func multiFileMigrationGetsTopTierAndATeam() {
        let advice = AdvisorEngine.advise(
            task: "Migración multi-archivo de bcrypt a argon2 en todo el repo, serán días de trabajo")
        // Deep + ambitious → the top tier (Fable, with Opus as the acceptable floor).
        #expect(advice.model == .fable5 || advice.model == .opus48)
        // A cross-repo migration warrants more than a solo agent.
        #expect(advice.strategy.roles.count > 1)
        #expect(!advice.strategy.subagentRoles.isEmpty)
        #expect(advice.effort == .high)
    }

    // MARK: - Loop detection

    @Test func untilTestsPassIsGoalBasedWithVerifiableGoal() {
        let advice = AdvisorEngine.advise(
            task: "corre los tests hasta que pasen y arregla el lint")
        #expect(advice.loopKind == .goalBased)
        // The drafted goal reuses the task's own finish line.
        #expect(advice.goalSuggestion.lowercased().contains("hasta que"))
        #expect(!advice.goalSuggestion.isEmpty)
    }

    @Test func everyMorningIsTimeBased() {
        let advice = AdvisorEngine.advise(task: "cada mañana resume los issues nuevos")
        #expect(advice.loopKind == .timeBased)
    }

    @Test func onFailureIsProactive() {
        let advice = AdvisorEngine.advise(
            task: "cuando falle el pipeline, investiga la causa y abre un informe")
        #expect(advice.loopKind == .proactive)
    }

    // MARK: - Cheap-model team downgrade

    @Test func fastModelDowngradesHeavyShapeWithExplicitStep() {
        // "explica" pushes the shape heuristic to research fan-out, but the task
        // is quick (Haiku), so the engine must scale down and say so in the path.
        let advice = AdvisorEngine.advise(
            task: "explica rápido cómo funciona este archivo, algo corto")
        #expect(advice.model == .haiku45)
        #expect(advice.shapeRationaleKey == "advisor.rationale.downgraded")
        #expect(advice.decisionPath.contains {
            $0.questionKey == "advisor.q.team" && !$0.answerIsYes
        })
    }

    // MARK: - Non-delegable work

    @Test func serialDebuggingCollapsesTeamButKeepsStrongModel() {
        // "investiga" trips the fan-out heuristic and the depth gate (→ strong model),
        // but a root-cause hunt is one serial chain of judgments — nothing to hand
        // off. The engine must collapse to a lean setup, say so in the path, and
        // (unlike the cheap-model downgrade) keep a capable model leading.
        let advice = AdvisorEngine.advise(
            task: "Investiga y depura por qué el checkout falla de forma intermitente en todo el repo; encuentra la causa raíz del fallo")
        #expect(advice.shapeRationaleKey == "advisor.rationale.nondelegable")
        #expect(advice.strategy.roles.count <= 2)          // executor + advisor, no fleet
        #expect(advice.model == .fable5 || advice.model == .opus48)
        #expect(advice.decisionPath.contains {
            $0.questionKey == "advisor.q.team" && !$0.answerIsYes
                && $0.evidenceKeys.contains("advisor.ev.serialDebug")
        })
    }

    @Test func delegableMultiFileWorkStillGetsATeam() {
        // Guard against over-firing: a genuinely splittable migration must NOT be
        // mistaken for non-delegable work.
        let advice = AdvisorEngine.advise(
            task: "Migración multi-archivo de bcrypt a argon2 en todo el repo, serán días de trabajo")
        #expect(advice.shapeRationaleKey != "advisor.rationale.nondelegable")
        #expect(!advice.strategy.subagentRoles.isEmpty)
    }

    // MARK: - Decision path shape

    @Test func pathIsNonEmptyAndStartsWithDepthQuestion() {
        let tasks = [
            "Resume este párrafo",
            "Migrate the whole repo to argon2 over several days",
            "corre los tests hasta que pasen",
            "",
        ]
        for task in tasks {
            let advice = AdvisorEngine.advise(task: task)
            #expect(!advice.decisionPath.isEmpty)
            #expect(advice.decisionPath.first?.questionKey == "advisor.q.depth")
            // Step ids are sequential, so the UI can rely on stable ordering.
            #expect(advice.decisionPath.map(\.id) == Array(0..<advice.decisionPath.count))
            // Evidence is capped at 3 per step.
            #expect(advice.decisionPath.allSatisfy { $0.evidenceKeys.count <= 3 })
        }
    }

    @Test func orchestratorRunsTheRecommendedModel() {
        let advice = AdvisorEngine.advise(task: "Resume este párrafo en dos líneas")
        #expect(advice.strategy.orchestrator?.model == advice.model)
    }

    // MARK: - Determinism

    @Test func sameInputProducesEqualAdvice() {
        let task = "Migración multi-archivo de bcrypt a argon2 en todo el repo, serán días de trabajo"
        let first = AdvisorEngine.advise(task: task)
        let second = AdvisorEngine.advise(task: task)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }
}
