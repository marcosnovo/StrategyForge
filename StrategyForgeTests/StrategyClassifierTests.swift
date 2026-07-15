//
//  StrategyClassifierTests.swift
//  StrategyForgeTests
//
//  Unit tests for the multi-axis task classifier and the shapes it can pick, including
//  the newly exposed shapes (scoutAct, triageRouter, rootCauseDebugging) and the new
//  Explore → Plan → Build → Review pipeline builder. Pure + deterministic, no mocks.
//

import Testing
import Foundation
@testable import Coral

struct StrategyClassifierTests {

    private func classify(_ s: String) -> StrategyGenerator.TaskProfile {
        StrategyGenerator.classify(s)
    }
    private func shape(_ s: String, _ connected: Set<AIProvider> = []) -> StrategyShape {
        StrategyGenerator.heuristicShape(for: s, connected: connected).0
    }

    // MARK: - Axis detection (EN + ES)

    @Test func detectsIntentAcrossAxes() {
        #expect(classify("help me understand this unfamiliar codebase").intent == .understand)
        #expect(classify("decide between Postgres and MySQL, compare the trade-offs").intent == .decide)
        #expect(classify("audit the payment flow for security issues").intent == .review)
        #expect(classify("triage the incoming issues and route each one").intent == .triage)
        #expect(classify("refactor the auth layer").intent == .change)
        #expect(classify("implement a new export feature").intent == .build)
        #expect(classify("just a quick experiment").intent == .quick)
    }

    @Test func spanishKeywordsClassifyTheSame() {
        #expect(classify("ayúdame a entender este código desconocido").intent == .understand)
        #expect(classify("decide la arquitectura y compara opciones").intent == .decide)
        #expect(classify("audita el flujo de pago").intent == .review)
        #expect(classify("triar los issues entrantes y enrutar cada uno").intent == .triage)
        #expect(classify("refactoriza la capa de autenticación").intent == .change)
    }

    @Test func detectsScopeBreadthAndFlags() {
        #expect(classify("rename this symbol across all files").scope == .repo)
        #expect(classify("fix the login module").scope == .module)
        #expect(classify("fix this typo").scope == .point)
        #expect(classify("process every module exhaustively in parallel").breadth == true)
        #expect(classify("run the tests until they pass").verifiable == true)
        #expect(classify("try to break and attack the auth").adversarial == true)
        #expect(classify("debug why it fails intermittently").serialDebug == true)
        #expect(classify("touch up the frontend and backend and database").multiDomain == true)
        #expect(classify("work in this unfamiliar legacy area").needsScouting == true)
    }

    // MARK: - Shape selection for the NEW shapes

    @Test func triageTaskPicksTriageRouter() {
        #expect(shape("triage the incoming issues and route each to the right owner") == .triageRouter)
    }

    @Test func serialDebugPicksRootCauseDebugging() {
        #expect(shape("debug why the API returns 500 intermittently") == .rootCauseDebugging)
        #expect(shape("depura por qué la API devuelve 500 de forma intermitente") == .rootCauseDebugging)
    }

    @Test func localizedChangeInAnUnfamiliarAreaPicksScoutAct() {
        // Build/change intent + a scouting need + NOT repo-wide → scout first, then act.
        #expect(shape("add a dark-mode toggle to this legacy component") == .scoutAct)
    }

    @Test func bigUnfamiliarBroadWorkPicksThePipeline() {
        // understand + repo + breadth → the full scout → plan → build → review pipeline.
        #expect(shape("understand the entire codebase exhaustively before the rewrite") == .pipeline)
    }

    // MARK: - Backward-compatible shapes still hold

    @Test func classicShapesAreUnchanged() {
        #expect(shape("help me understand this unfamiliar codebase") == .researchFanout)
        #expect(shape("just a quick experiment") == .solo)
        #expect(shape("rename this symbol across all files") == .orchestratorWorkers)
        #expect(shape("fix the login bug") == .executorAdvisor)
        #expect(shape("try to break and attack the auth to harden it") == .sparring)
        #expect(shape("decide between Postgres and MySQL and compare the trade-offs") == .debateConsensus)
    }

    @Test func broadTaskPrefersSpecialistsWithSeveralProviders() {
        #expect(shape("process every module exhaustively in parallel") == .orchestratorWorkers)
        #expect(shape("process every module exhaustively in parallel",
                      [.claude, .openai, .gemini]) == .domainSpecialists)
    }

    // MARK: - Determinism

    @Test func classificationIsDeterministic() {
        let task = "understand the entire codebase exhaustively before the rewrite"
        #expect(classify(task) == classify(task))
        #expect(shape(task) == shape(task))
    }

    // MARK: - Every shape builds a legal strategy

    @Test func newShapesBuildLegalStrategies() {
        for shape in [StrategyShape.scoutAct, .triageRouter, .rootCauseDebugging, .pipeline] {
            let s = StrategyGenerator.buildStrategy(shape: shape, teamSize: 3)
            #expect(s.orchestrator != nil, "\(shape) needs an orchestrator")
            #expect(s.roles.count >= 2, "\(shape) should be a real team")
            #expect(s.validate().isEmpty, "\(shape) must be a legal topology")
        }
    }

    @Test func pipelineBuilderHasTheFourPhases() {
        let s = StrategyLibrary.explorePlanBuildReview()
        let kinds = Set(s.roles.map(\.role))
        #expect(kinds.contains(.orchestrator))
        #expect(kinds.contains(.researcher))   // scout
        #expect(kinds.contains(.worker))        // implementer
        #expect(kinds.contains(.reviewer))
        #expect(s.validate().isEmpty)
    }

    @Test func everyLibraryTemplateIsLegal() {
        for s in StrategyLibrary.all {
            #expect(s.orchestrator != nil)
            #expect(s.validate().isEmpty, "\(s.name) must be legal")
        }
    }
}
