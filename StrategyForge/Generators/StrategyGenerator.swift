//
//  StrategyGenerator.swift
//  StrategyForge
//
//  "Describe your task → get a bespoke strategy." Uses Apple's on-device
//  FoundationModels to pick the team SHAPE and size that fit a plain-language
//  task, then builds a real Strategy from the known-good library templates and
//  runs it through autoFixed() so the result can NEVER be an illegal topology.
//  Falls back to a keyword heuristic when Apple Intelligence is unavailable.
//
//  The model only ever chooses among the app's vetted building blocks — it does
//  not free-form author frontmatter — which keeps generation faithful.
//

import Foundation
import FoundationModels

/// The team shape the model may choose. Mirrors the library's templates.
@Generable(description: "The shape of a multi-agent team for a coding task")
enum StrategyShape {
    case solo
    case executorAdvisor
    case plannerReviewer
    case orchestratorWorkers
    case researchFanout
    case debateConsensus
    case domainSpecialists
    case sparring
    /// Cheap read-only scout maps the terrain, then an implementer acts on a brief.
    case scoutAct
    /// A cheap triager classifies/routes incoming work to the right handler.
    case triageRouter
    /// Serial root-cause hunt: reproduce → locate → fix → verify (non-delegable).
    case rootCauseDebugging
    /// Full pipeline for large, unfamiliar, high-stakes work: scout → plan →
    /// implement → review. The deepest flow (a new composite builder).
    case pipeline
}

/// The model's structured recommendation.
@Generable(description: "A recommended multi-agent setup for a coding task")
struct StrategyRecommendation {
    @Guide(description: "The team shape that best fits the task")
    var shape: StrategyShape

    @Guide(description: "Number of parallel workers/specialists, used only when the shape fans out", .range(1...6))
    var teamSize: Int

    @Guide(description: "One short sentence explaining why this shape fits")
    var rationale: String
}

enum StrategyGenerator {

    struct Result {
        let strategy: Strategy
        /// The model's one-line reasoning (nil when the heuristic fallback was used).
        let aiRationale: String?
        let usedAI: Bool
    }

    /// Whether the on-device model is ready (Apple Intelligence on + downloaded).
    static var isAIAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Coarse availability of the on-device model, for the UI to explain the
    /// recommendation source and offer to turn Apple Intelligence on.
    enum AIStatus: Equatable { case available, notEnabled, notReady, notEligible }
    static var aiStatus: AIStatus {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable(.deviceNotEligible): return .notEligible
        @unknown default: return .notEligible
        }
    }

    private static let instructions = """
    You design agent teams for the Claude Code CLI. Given a coding task, choose the \
    team SHAPE that fits and a team size. Prefer the simplest shape that works. Use a \
    fan-out shape (orchestratorWorkers, researchFanout, domainSpecialists) only when \
    the task clearly splits into parallel parts. Use scoutAct when an unfamiliar area \
    should be mapped cheaply before changing it; triageRouter to classify/route incoming \
    work; rootCauseDebugging for a serial "why does it fail" hunt; and pipeline (scout → \
    plan → implement → review) for large, unfamiliar, high-stakes changes. Keep the \
    rationale to one short sentence.
    """

    /// Produce a strategy for a plain-language task.
    static func generate(from task: String) async -> Result {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAIAvailable, !trimmed.isEmpty {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: trimmed, generating: StrategyRecommendation.self)
                let rec = response.content
                return Result(strategy: buildStrategy(shape: rec.shape, teamSize: rec.teamSize),
                              aiRationale: rec.rationale, usedAI: true)
            } catch {
                // Fall through to the heuristic on any model error.
            }
        }
        let (shape, size) = heuristicShape(for: trimmed)
        return Result(strategy: buildStrategy(shape: shape, teamSize: size),
                      aiRationale: nil, usedAI: false)
    }

    /// Build a real, legal Strategy from a shape + size. Internal for testing.
    static func buildStrategy(shape: StrategyShape, teamSize: Int) -> Strategy {
        var s: Strategy
        switch shape {
        case .solo:                s = StrategyLibrary.solo()
        case .executorAdvisor:     s = StrategyLibrary.executorAdvisor()
        case .plannerReviewer:     s = StrategyLibrary.plannerImplementersReviewer()
        case .orchestratorWorkers: s = StrategyLibrary.orchestratorWorkers()
        case .researchFanout:      s = StrategyLibrary.researchFanout()
        case .debateConsensus:     s = StrategyLibrary.debateConsensus()
        case .domainSpecialists:   s = StrategyLibrary.domainSpecialists()
        case .sparring:            s = StrategyLibrary.sparring()
        case .scoutAct:            s = StrategyLibrary.scoutAct()
        case .triageRouter:        s = StrategyLibrary.triageRouter()
        case .rootCauseDebugging:  s = StrategyLibrary.rootCauseDebugging()
        case .pipeline:            s = StrategyLibrary.explorePlanBuildReview()
        }
        // Scale the primary fan-out role (the one that already has count > 1).
        let size = max(1, min(teamSize, 6))
        let subagentIndices = s.roles.indices.filter { !s.roles[$0].isOrchestrator }
        if let idx = subagentIndices.max(by: { s.roles[$0].count < s.roles[$1].count }),
           s.roles[idx].count > 1 {
            s.roles[idx].count = size
        }
        // Guarantee a legal topology no matter what the model returned.
        return s.autoFixed()
    }

    /// The deterministic classifier the whole app relies on when Apple Intelligence is
    /// off (and the fallback otherwise). Reads the task on several independent axes, then
    /// maps that profile → a team shape + size. `connected` makes the SHAPE provider-
    /// aware. Pure and cheap (substring scans on normalized text); `connected` defaults
    /// to empty so existing callers keep single-provider behavior.
    static func heuristicShape(for task: String,
                               connected: Set<AIProvider> = []) -> (StrategyShape, Int) {
        shape(for: classify(task), connected: connected)
    }

    // MARK: - Multi-axis task classifier

    /// What the task primarily asks for.
    enum TaskIntent: String, Equatable {
        case understand, decide, review, triage, change, build, harden, quick, general
    }
    /// How much of the codebase the task spans.
    enum TaskScope: String, Equatable { case point, module, repo }

    /// A deterministic, multi-axis reading of a task. Pure + cheap; drives shape
    /// selection and is exposed for the UI's "why" and for tests.
    struct TaskProfile: Equatable {
        var intent: TaskIntent
        var scope: TaskScope
        var breadth: Bool        // explicit parallel / exhaustive coverage
        var verifiable: Bool     // a checkable finish line (tests / lint / build / score)
        var adversarial: Bool    // attack / break / harden / red-team
        var serialDebug: Bool    // a non-delegable root-cause chain
        var multiDomain: Bool    // spans ≥2 distinct domains (frontend/backend/db/…)
        var needsScouting: Bool  // an unfamiliar area worth mapping first
        var willChange: Bool     // the task ends in a change/build (not pure research)
        /// How decisively the task classified (0…1). Low confidence → the UI can offer
        /// to ask a clarifying question rather than commit to a shape.
        var confidence: Double

        /// A low-confidence read is one the UI shouldn't present as certain.
        var isConfident: Bool { confidence >= 0.5 }
    }

    /// Read a task into a `TaskProfile`. Bilingual (EN + ES): the text is lowercased and
    /// diacritics folded, so every keyword below is stored accent-free.
    static func classify(_ task: String) -> TaskProfile {
        let t = " " + task.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")) + " "
        func any(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        func hits(_ words: [String]) -> Int { words.reduce(0) { t.contains($1) ? $0 + 1 : $0 } }

        let serialDebug = any(["root cause", "root-cause", "causa raiz", "raiz del",
            "why is", "why does", "why the", "why it", "why are", "por que falla",
            "por que se", "por que da", "por que no funciona", "debug", "depura",
            "trace through", "step through", "stack trace", "flaky", "intermitente",
            "intermittent", "bisect"])
        let adversarial = any(["adversarial", "attack", "atacar", "break ", "romper",
            "exploit", "harden", "endurec", "red team", "red-team", "pentest",
            "penetration", "sparring", "fuzz"])
        let breadth = any(["exhaustiv", "varios frentes", "varias areas", "desde varios",
            "en varios", "en paralelo", "in parallel", "several fronts", "multiple angles",
            "many areas", "backlog", "cada modulo", "every module", "every component",
            "batch", "todo el codigo", "entire codebase", "whole codebase"])
        let verifiable = any(["test", "lint", "compil", "build succeeds", "deploy",
            "hasta que", "until", "score", "pasen", "que pase", "green "])
        let needsScouting = any(["unfamiliar", "legacy", "explore", "explora", "investiga",
            "research", "how does", "como funciona", "map the", "no conozco", "desconocid",
            "understand", "entender"])
        let repo = any(["codebase", "code base", "repo", "across all", "all files",
            "every file", "entire", "whole ", "todo el", "toda la", "project-wide",
            "monorepo", "microservice"])
        let module = any(["module", "modulo", "component", "componente", "service",
            "servicio", "file", "archivo", "class ", "clase", "function", "funcion",
            "endpoint"])
        let scope: TaskScope = repo ? .repo : (module ? .module : .point)
        let multiDomain = hits(["frontend", "backend", "database", "base de datos",
            "security", "seguridad", "infra", "api", "mobile", "ui ", "devops"]) >= 2
        // Does the task ultimately CHANGE the code (vs. pure understanding)? Separates a
        // research fan-out from the full build pipeline.
        let willChange = any(["rewrite", "reescrib", "refactor", "migrate", "migrar",
            "implement", "implementa", "build", "construir", "add ", "create", "crea",
            "feature", "funcionalidad", "change", "cambia", " port ", "upgrade"])

        // Intent — first matching group wins; the order resolves ambiguous tasks
        // (e.g. "explain then refactor" reads as understand, not change). NOTE:
        // "unfamiliar"/"legacy" are scouting SIGNALS, not an understand intent — a
        // "change this unfamiliar module" is a change that needs scouting, not research.
        let intent: TaskIntent
        if any(["understand", "explain", "explica", "explora", "explore", "investiga",
                "investigar", "research", "how does", "como funciona",
                "entender", "comprender", "study"]) {
            intent = .understand
        } else if any(["architecture", "arquitectura", "design", "disen", "trade-off",
                "tradeoff", "decide", "decidir", "compare", "comparar", "option",
                "opcion", "choose", "elegir", "consensus", "consenso", "evaluate", "evalua"]) {
            intent = .decide
        } else if any(["review", "revis", "audit", "auditar", "auditoria", "verify",
                "verificar", "qa", "code review", "inspecc", "coverage", "cobertura",
                "production", "critical", "critico", "produccion", "safe"]) {
            intent = .review
        } else if any(["triage", "triar", "router", "route ", "routing", "classify",
                "clasific", "categor", "dispatch", "sort into", "prioriti", "prioriza"]) {
            intent = .triage
        } else if adversarial {
            intent = .harden
        } else if any(["refactor", "migrate", "migrar", "migracion", "rename", "renombr",
                "bulk", "masivo", "convert", " port ", "upgrade", "actualiza", "cleanup",
                "fix", "arregl", "replace", "reemplaza", "across", "todos los", "en todo",
                "change", "cambia", "modif", "tweak", "adjust", "edit "]) {
            intent = .change
        } else if any(["implement", "implementa", "add ", "anad", "create", "crea",
                "build", "construir", "feature", "funcionalidad", "nuevo", "nueva",
                "write", "escribe", "generate", "genera"]) {
            intent = .build
        } else if any(["experiment", "experimenta", "quick", "rapid", "small", "pequen",
                "play", "prueba", "try "]) {
            intent = .quick
        } else {
            intent = .general
        }

        // Confidence: how decisively the task read. A clear intent (or a decisive flag
        // like a debug hunt / adversarial ask) plus supporting axes reads high; a bare
        // `general` task with no axes reads low (the UI can then offer to clarify).
        var axes = 0
        for on in [breadth, verifiable, adversarial, serialDebug, multiDomain,
                   needsScouting, scope != .point] where on { axes += 1 }
        let decisive = intent != .general || serialDebug || adversarial
        let confidence = min(1.0, (decisive ? 0.6 : 0.35) + 0.1 * Double(axes))

        return TaskProfile(intent: intent, scope: scope, breadth: breadth,
                           verifiable: verifiable, adversarial: adversarial,
                           serialDebug: serialDebug, multiDomain: multiDomain,
                           needsScouting: needsScouting, willChange: willChange,
                           confidence: confidence)
    }

    /// Map a task profile (+ what's connected) to a concrete shape + team size. Pure and
    /// total — every profile resolves to exactly one shape.
    static func shape(for p: TaskProfile, connected: Set<AIProvider> = []) -> (StrategyShape, Int) {
        let multi = connected.count > 1
        let size = p.breadth ? 4 : 3
        // A broad, splittable task: distinct specialists when several providers can each
        // take a seat, else identical workers.
        func fanout() -> (StrategyShape, Int) {
            multi ? (.domainSpecialists, size) : (.orchestratorWorkers, size)
        }

        // 1. Serial root-cause hunt — non-delegable (advise() also enforces this).
        if p.serialDebug { return (.rootCauseDebugging, 1) }
        // 2. Adversarial hardening.
        if p.intent == .harden { return (.sparring, 1) }
        // 3. Classify / route incoming work.
        if p.intent == .triage { return (.triageRouter, 1) }
        // 4. Understand / explore.
        if p.intent == .understand {
            // Large, unfamiliar, broad understanding that LEADS TO a change → the full
            // scout → plan → build → review pipeline; pure research → a research fan-out.
            if p.scope == .repo && p.breadth && p.willChange { return (.pipeline, size) }
            return (.researchFanout, size)
        }
        // 5. Decide / design.
        if p.intent == .decide {
            return (p.multiDomain || p.breadth) ? (.domainSpecialists, size) : (.debateConsensus, 1)
        }
        // 6. Review / audit — broad, multi-domain, or repo-wide → a specialist per angle.
        if p.intent == .review {
            return (p.breadth || p.multiDomain || p.scope == .repo) ? (.domainSpecialists, size)
                                                                     : (.plannerReviewer, 1)
        }
        // 7. Change (refactor / migrate / bulk edit).
        if p.intent == .change {
            if p.scope == .repo || p.breadth { return fanout() }
            if p.multiDomain { return (.domainSpecialists, size) }
            if p.needsScouting { return (.scoutAct, 1) }   // localized change in an unfamiliar area
            return (.executorAdvisor, 1)
        }
        // 8. Build a feature.
        if p.intent == .build {
            if p.scope == .repo && p.breadth { return fanout() }
            if p.multiDomain { return (.domainSpecialists, size) }
            if p.verifiable { return (.plannerReviewer, 1) }
            if p.needsScouting { return (.scoutAct, 1) }
            return (.executorAdvisor, 1)
        }
        // 9. Quick / trivial.
        if p.intent == .quick { return (.solo, 1) }
        // 10. Any remaining breadth signal → a small fan-out.
        if p.breadth { return fanout() }
        // 11. Default: a lean executor + advisor.
        return (.executorAdvisor, 1)
    }
}
