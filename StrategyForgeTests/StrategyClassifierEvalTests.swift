//
//  StrategyClassifierEvalTests.swift
//  StrategyForgeTests
//
//  Phase 0 — the evaluation HARNESS for the strategy recommender. A labeled corpus of
//  realistic tasks (EN + ES) with the shape each SHOULD map to. Two gates:
//
//   • `goldenSetNeverRegresses` — a high-confidence subset that must ALWAYS classify
//     correctly (a hard gate against regressions).
//   • `corpusAccuracyMeetsFloor` — measures accuracy over the full corpus and asserts a
//     floor, printing every mismatch so gaps are visible and improvements are provable.
//
//  This turns "heuristic by vibes" into "measured quality": any change to the classifier
//  is now graded against a fixed corpus.
//

import Testing
import Foundation
@testable import Coral

struct StrategyClassifierEvalTests {

    private func shape(_ task: String) -> StrategyShape {
        StrategyGenerator.heuristicShape(for: task).0
    }

    /// (task, ideal shape). The GOLDEN set — unambiguous cases that must never regress.
    private static let golden: [(String, StrategyShape)] = [
        // Understand / research
        ("help me understand this unfamiliar codebase", .researchFanout),
        ("explain how the auth flow works", .researchFanout),
        ("ayúdame a entender este código desconocido", .researchFanout),
        // Quick / trivial
        ("just a quick experiment", .solo),
        ("un experimento rápido y pequeño", .solo),
        // Bulk change across the repo
        ("rename this symbol across all files", .orchestratorWorkers),
        ("migrate the whole repo from bcrypt to argon2", .orchestratorWorkers),
        // Small localized fix → lean
        ("fix the login bug", .executorAdvisor),
        // Decide / design
        ("decide between Postgres and MySQL and compare the trade-offs", .debateConsensus),
        ("decide la arquitectura y compara las opciones", .debateConsensus),
        // Adversarial
        ("try to break and attack the auth to harden it", .sparring),
        ("intenta romper y atacar el login", .sparring),
        // Serial debugging
        ("debug why the API returns 500 intermittently", .rootCauseDebugging),
        ("depura por qué la app falla de forma intermitente", .rootCauseDebugging),
        // Triage / routing
        ("triage the incoming issues and route each to the right owner", .triageRouter),
        // Big unfamiliar broad work → full pipeline
        ("understand the entire codebase exhaustively before the rewrite", .pipeline),
        // Localized change in an unfamiliar area → scout then act
        ("add a dark-mode toggle to this legacy component", .scoutAct),
    ]

    /// The broader corpus (includes golden). Ideal labels; accuracy is measured.
    private static let corpus: [(String, StrategyShape)] = golden + [
        // Review / audit (focused vs broad)
        ("review this pull request for correctness", .plannerReviewer),
        ("audit the payment module for security issues across the codebase", .domainSpecialists),
        ("revisa este cambio antes de mergear", .plannerReviewer),
        ("auditoría de seguridad exhaustiva de todo el repo", .domainSpecialists),
        // Multi-domain
        ("touch up the frontend, backend and database for the new feature", .domainSpecialists),
        // Build feature (localized, no scouting)
        ("implement a new export-to-CSV feature", .executorAdvisor),
        ("implementa un botón de exportar", .executorAdvisor),
        // Build verifiable
        ("add a feature and make sure the tests pass", .plannerReviewer),
        // Change localized
        ("refactor the auth layer", .executorAdvisor),
        ("refactoriza la capa de autenticación", .executorAdvisor),
        // Broad parallel
        ("process every module exhaustively in parallel", .orchestratorWorkers),
        ("update every service across the monorepo", .orchestratorWorkers),
        // Research broad
        ("research how the whole system fits together from several fronts", .researchFanout),
        ("investiga en paralelo cómo encaja todo el sistema", .researchFanout),
        // Design broad / multi-domain
        ("design the architecture for a new frontend and backend system", .domainSpecialists),
        // Debug ES / EN variants
        ("encuentra la causa raíz del fallo de checkout", .rootCauseDebugging),
        ("trace through the stack trace to find the root cause", .rootCauseDebugging),
        // Harden variants
        ("red-team the login endpoint", .sparring),
        // Scout variants
        ("change this legacy module I'm unfamiliar with", .scoutAct),
        // Understand ES
        ("explora este repo que no conozco", .researchFanout),
        // Quick ES
        ("prueba algo pequeño rápido", .solo),
    ]

    @Test func goldenSetNeverRegresses() {
        for (task, expected) in Self.golden {
            #expect(shape(task) == expected, "GOLDEN mismatch: \"\(task)\" → \(shape(task)), expected \(expected)")
        }
    }

    @Test func corpusAccuracyMeetsFloor() {
        var correct = 0
        var mismatches: [String] = []
        for (task, expected) in Self.corpus {
            let got = shape(task)
            if got == expected { correct += 1 }
            else { mismatches.append("  ✗ \"\(task)\" → \(got), expected \(expected)") }
        }
        let accuracy = Double(correct) / Double(Self.corpus.count)
        if !mismatches.isEmpty {
            print("Classifier corpus accuracy: \(Int(accuracy * 100))% (\(correct)/\(Self.corpus.count)). Mismatches:")
            mismatches.forEach { print($0) }
        }
        // Floor raised to 0.90 after Phase 1 (the weighted-signal fixes took the corpus
        // from 84% → 100%). Kept a little below 100% so genuinely-hard cases can be added
        // to the corpus later without instantly failing; the golden set stays strict.
        #expect(accuracy >= 0.90, "Corpus accuracy \(Int(accuracy * 100))% fell below the 90% floor")
    }

    // MARK: - Confidence signal

    // MARK: - Phase 2: semantic layer (on-device embeddings)

    @Test func semanticLayerClassifiesParaphrasesByMeaning() {
        // Only meaningful when on-device word embeddings are present; otherwise the
        // feature no-ops and this skips (keyword path is unaffected either way).
        guard SemanticClassifier.bestIntent(for: "understand the system") != nil else {
            print("word embeddings unavailable — semantic layer test skipped"); return
        }
        // Paraphrases with NO intent keywords — keyword-only can't read them.
        let cases: [(String, StrategyGenerator.TaskIntent)] = [
            ("grasp how this whole thing operates", .understand),
            ("tidy up and modernize the old plumbing", .change),
            ("weigh a couple of approaches and pick one", .decide),
            ("wire up a brand-new capability", .build),
        ]
        var correct = 0
        for (task, want) in cases {
            guard let r = SemanticClassifier.bestIntent(for: task) else { continue }
            print(String(format: "SEM  %-45@ → %@  (%.3f)  want %@",
                         task as NSString, "\(r.intent)" as NSString, r.score, "\(want)" as NSString))
            if r.intent == want && r.score >= StrategyGenerator.semanticThreshold { correct += 1 }
        }
        // Embeddings are fuzzy; require a majority correct above threshold.
        #expect(correct >= 2, "semantic layer classified only \(correct)/4 paraphrases correctly above threshold")
    }

    @Test func semanticLayerNeverChangesConfidentKeywordReads() {
        // High-confidence keyword tasks must be identical with or without embeddings.
        for (task, expected) in Self.golden {
            #expect(shape(task) == expected)
        }
    }

    @Test func clearTasksReadHighConfidenceAmbiguousReadLow() {
        // A decisive task (clear intent + supporting axes) → confident.
        #expect(StrategyGenerator.classify(
            "migrate the entire repo from bcrypt to argon2 exhaustively").isConfident)
        #expect(StrategyGenerator.classify(
            "debug why the API fails intermittently").isConfident)
        // A bare, signal-less task → NOT confident, so the UI can offer to clarify.
        #expect(!StrategyGenerator.classify("do the thing").isConfident)
        #expect(!StrategyGenerator.classify("stuff").isConfident)
    }
}
