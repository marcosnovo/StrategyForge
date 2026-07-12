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

/// The team shape the model may choose. Mirrors the library's 8 templates.
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

    private static let instructions = """
    You design agent teams for the Claude Code CLI. Given a coding task, choose the \
    team SHAPE that fits and a team size. Prefer the simplest shape that works. Use a \
    fan-out shape (orchestratorWorkers, researchFanout, domainSpecialists) only when \
    the task clearly splits into parallel parts. Keep the rationale to one short sentence.
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

    /// Keyword fallback when the on-device model isn't available. Internal for testing.
    static func heuristicShape(for task: String) -> (StrategyShape, Int) {
        let t = task.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        // Does the task explicitly ask for BREADTH / parallel coverage ("from several
        // fronts", "exhaustive", "in parallel", "a prioritized backlog", "across N
        // areas")? That's the strongest signal for a fan-out team + supervisor, so it
        // upgrades otherwise-single-agent shapes (a broad review → specialists, etc.).
        let breadth = has(["exhaustiv", "varios frentes", "varias areas", "varias áreas",
                           "desde varios", "en varios", "en paralelo", "in parallel",
                           "several fronts", "multiple angles", "many areas", "backlog",
                           "cada modulo", "cada módulo", "every module", "todo el codigo",
                           "todo el código", "entire codebase", "whole codebase"])

        if has(["understand", "explain", "explore", "unfamiliar", "how does",
                "entender", "explica", "explora", "investiga", "investigar", "research"]) {
            return (.researchFanout, breadth ? 4 : 3)
        }
        if has(["across", "all files", "every file", "bulk", "migrate", "rename",
                "masivo", "todos los", "en todo", "migrar", "migración", "migracion"]) {
            return (.orchestratorWorkers, breadth ? 4 : 3)
        }
        // A code review / audit: broad ("from several fronts") → domain specialists
        // (each covers an angle); a focused one → planner → reviewer.
        if has(["review", "audit", "revisar", "auditar", "auditoria", "auditoría",
                "verify", "verificar", "production", "critical", "safe",
                "crítico", "producción", "qa"]) {
            return breadth ? (.domainSpecialists, 4) : (.plannerReviewer, 1)
        }
        if has(["design", "architecture", "trade-off", "tradeoff", "decide", "compare",
                "arquitectura", "diseñar", "decidir"]) {
            return breadth ? (.domainSpecialists, 4) : (.debateConsensus, 1)
        }
        if has(["frontend", "backend", "database", "security", "full-stack", "fullstack",
                "dominio", "especialista"]) {
            return (.domainSpecialists, breadth ? 4 : 3)
        }
        if has(["adversarial", "break", "attack", "harden", "sparring", "romper", "atacar"]) {
            return (.sparring, 1)
        }
        if has(["experiment", "try", "quick", "small", "play",
                "experimentar", "probar", "rápido", "pequeño"]) {
            return (.solo, 1)
        }
        // Any remaining breadth signal → a small fan-out beats the solo/exec default.
        if breadth { return (.orchestratorWorkers, 3) }
        return (.executorAdvisor, 1)
    }
}
