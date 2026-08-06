//
//  AdvisorEngine.swift
//  StrategyForge
//
//  The Advisor's brain: a pure, deterministic decision tree that maps a
//  plain-language task to a recommended Claude model, team strategy, loop kind
//  and effort level — WITHOUT creating anything. Every branch taken is recorded
//  as a DecisionStep so the UI can render the path visually (like Anthropic's
//  "which model should I use" flowchart). No UI, no network, fully testable.
//
//  Matching is bilingual (EN + ES): the task is lowercased and diacritics are
//  folded ("rápido" → "rapido"), so every keyword below is stored in that
//  normalized form (no accents, ñ → n).
//

import Foundation

enum AdvisorEngine {

    // MARK: - Output types

    /// One node of the decision path: the question asked, the answer taken, and
    /// which signals fired (as localization keys, capped at 3 for the UI).
    struct DecisionStep: Identifiable, Hashable {
        let id: Int
        let questionKey: String    // e.g. "advisor.q.depth"
        let answerIsYes: Bool
        let answerKey: String      // e.g. "advisor.a.depth.yes"
        let evidenceKeys: [String] // matched-signal explanations, may be empty
    }

    /// The full recommendation. Semantic equality: the library builders mint a
    /// fresh Strategy id on every call and StrategyCost is a derived value, so
    /// two identical recommendations must still compare equal (determinism).
    struct Advice: Hashable {
        let model: ClaudeModel
        let strategy: Strategy
        let shapeRationaleKey: String
        let loopKind: LoopKind
        let effort: CostEffort
        let decisionPath: [DecisionStep]
        /// A one-line verifiable goal drafted from the task text (best effort).
        let goalSuggestion: String
        let estimatedCost: StrategyCost
        /// Free-text rationale from the on-device model, when AI upgraded the shape
        /// (nil for the pure deterministic path).
        var aiRationale: String? = nil
        /// True when Apple Intelligence shaped this recommendation (vs the local
        /// deterministic engine) — so the UI can label the source honestly.
        var usedAI: Bool = false
        /// Cross-provider assignments made on top of the base advice. Empty on the
        /// Claude-only path; populated when >1 provider is connected and the engine
        /// mixed providers per role (see `AdvisorEngine+Providers`).
        var providerPicks: [ProviderPick] = []

        static func == (lhs: Advice, rhs: Advice) -> Bool {
            lhs.model == rhs.model
                && lhs.strategy.name == rhs.strategy.name
                && lhs.strategy.roles.map(roleSignature) == rhs.strategy.roles.map(roleSignature)
                && lhs.shapeRationaleKey == rhs.shapeRationaleKey
                && lhs.loopKind == rhs.loopKind
                && lhs.effort == rhs.effort
                && lhs.decisionPath == rhs.decisionPath
                && lhs.goalSuggestion == rhs.goalSuggestion
                && lhs.estimatedCost.perRun == rhs.estimatedCost.perRun
                && lhs.providerPicks == rhs.providerPicks
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(model)
            hasher.combine(strategy.name)
            hasher.combine(strategy.roles.map(Advice.roleSignature))
            hasher.combine(shapeRationaleKey)
            hasher.combine(loopKind)
            hasher.combine(effort)
            hasher.combine(decisionPath)
            hasher.combine(goalSuggestion)
            hasher.combine(providerPicks)
        }

        /// Identity-free fingerprint of a role (ids are minted per build). Includes
        /// the provider + provider-model so a cross-provider reassignment is a real,
        /// observable difference (not folded away by equality/hash).
        private static func roleSignature(_ role: AgentRole) -> String {
            "\(role.name)|\(role.model.rawValue)|\(role.count)|\(role.provider.rawValue)|\(role.providerModelID ?? "")"
        }
    }

    // MARK: - Signal tables (keywords pre-normalized: lowercase, no diacritics)

    /// A named group of keywords; if any keyword occurs in the normalized task
    /// the group "fires" and contributes its evidence key to the decision step.
    private struct SignalGroup {
        let evidenceKey: String
        let keywords: [String]
    }

    /// Q1 — does the task need more than a quick answer?
    private static let depthGroups: [SignalGroup] = [
        // Stems on purpose so a stem catches every conjugation once diacritics fold:
        // "implement" covers implementa(r), "investiga" covers investigate/investigar,
        // "disen" covers diseña(r). Broadened to how people actually phrase build-type work
        // (create, make, add, fix, improve, write, plan, analyze, review…), EN + ES, so the
        // advisor isn't brittle to exact wording. (Image "crea/genera" is caught earlier.)
        SignalGroup(evidenceKey: "advisor.ev.multistep", keywords: [
            "migrate", "migrar", "refactor", "refactoriza", "audit", "audita",
            "build", "construir", "construye", "implement", "implementa", "investiga",
            "design", "disen", "develop", "desarrolla", "desarrollar", "program", "programa",
            "code", "codifica", "create", "crea", "crear", "make", "haz", "hazme", "monta",
            "montar", "add", "anade", "anadir", "agrega", "agregar", "integra", "integrar",
            "optimiz", "optimiza", "improve", "mejora", "mejorar", "fix", "arregla", "arreglar",
            "soluciona", "resuelve", "analyze", "analiza", "analizar", "review", "revisa",
            "revisar", "write", "escribe", "escribir", "redacta", "redactar", "genera", "generar",
            "plan ", "planifica", "planificar", "report", "informe", "document", "documenta",
        ]),
        SignalGroup(evidenceKey: "advisor.ev.scope", keywords: [
            "repo", "test", "multiple files", "varios archivos", "muchos archivos",
            "all files", "todos los archivos", "en todo", "dias", "days", "hours", "horas",
            "project", "proyecto", "codebase", "base de codigo", "whole app", "toda la app",
            "sistema", "system", "pipeline", "backend", "frontend", "app entera", "aplicacion",
        ]),
        // Explicit breadth ("from several fronts", "exhaustive", "in parallel", a
        // "prioritized backlog") is real depth: it warrants a strong model + a team,
        // so it must NOT collapse to the cheap-model executor+advisor downgrade.
        SignalGroup(evidenceKey: "advisor.ev.breadth", keywords: [
            "exhaustiv", "varios frentes", "desde varios", "en varios", "en paralelo",
            "in parallel", "several fronts", "multiple angles", "many areas", "backlog",
            "varias areas", "auditoria",
        ]),
    ]

    /// Q2 — is maximum speed / minimal tokens the priority? (quick-answer branch)
    private static let speedGroups: [SignalGroup] = [
        SignalGroup(evidenceKey: "advisor.ev.speedWords", keywords: [
            "summar", "resum", "translat", "traduc", "list", "short", "corto",
            "quick", "rapid", "classif", "clasific",
            // Natural "just a quick question" phrasings → a light, fast single model.
            "tldr", "tl;dr", "brevemente", "en breve", "quick question", "pregunta rapida",
            "dame", "dime", "que es", "what is", "what's", "explica", "explain", "define",
        ]),
    ]

    /// Q3 — is this the hardest, most ambitious work? (deep-task branch)
    private static let hardestGroups: [SignalGroup] = [
        SignalGroup(evidenceKey: "advisor.ev.ambition", keywords: [
            "architecture", "arquitectura", "multi-day", "varios dias", "deep research",
            "investigacion profunda", "end to end", "end-to-end", "de punta a punta",
            "from scratch", "desde cero", "sistema completo", "whole system", "ambitious",
            "ambicioso", "gran proyecto", "big project", "complejo de verdad",
        ]),
        SignalGroup(evidenceKey: "advisor.ev.migration", keywords: [
            "migration", "migracion",
        ]),
        SignalGroup(evidenceKey: "advisor.ev.orchestration", keywords: [
            "orchestrat", "orquestar", "orquesta", "many agents", "muchos agentes",
        ]),
    ]

    /// Work with no delegable components: a serial root-cause investigation where
    /// the accumulated context IS the work — you can't hand off half a debugging
    /// chain. When the shape heuristic reaches for a team on this kind of task,
    /// delegation has no leverage over cost, so the shape collapses to one capable
    /// agent instead. Keywords are high-precision on purpose (diagnosis, not just
    /// "bug"), to avoid collapsing genuinely splittable work.
    private static let nonDelegableGroups: [SignalGroup] = [
        SignalGroup(evidenceKey: "advisor.ev.serialDebug", keywords: [
            "root cause", "root-cause", "causa raiz", "raiz del",
            "why is", "why does", "why the", "why it", "why are",
            "por que falla", "por que se", "por que da", "por que no funciona",
            "debug", "depura", "trace through", "step through", "stack trace",
            "flaky", "intermitente", "intermittent", "bisect",
        ]),
    ]

    /// Loop-kind signals, checked in priority order: goal → time → event.
    private static let goalLoopGroup = SignalGroup(evidenceKey: "advisor.ev.goalWords", keywords: [
        "hasta que", "until", "tests pass", "pasen", "lint", "bug fix", "arregl",
        "fixed", "score", "quede limpio",
    ])
    private static let timeLoopGroup = SignalGroup(evidenceKey: "advisor.ev.timeWords", keywords: [
        "daily", "diario", "diaria", " cada ", "every morning", "every day",
        "every week", "each morning", "semanal", "weekly", "monitor", "vigila",
    ])
    private static let eventLoopGroup = SignalGroup(evidenceKey: "advisor.ev.eventWords", keywords: [
        " pr ", "pull request", "webhook", "on failure", "cuando falle",
        "cuando falla", "si falla", "when it fails", "issue triage",
    ])

    /// Verifiable finish lines for the goal draft: (task keyword, English goal).
    private static let verifiableMarkers: [(keyword: String, goal: String)] = [
        ("test", "the tests pass"), ("lint", "the lint is clean"),
        ("build", "the build succeeds"), ("compil", "the build succeeds"),
        ("deploy", "the deploy is verified"), ("bug", "the bug is fixed"),
        ("score", "the target score is reached"),
    ]

    // MARK: - Public API

    /// Run the decision tree on a task. Pure and deterministic: the same input
    /// (task + connected set) always produces the same (semantically equal) Advice.
    /// `connected` lets the SHAPE itself be provider-aware (e.g. a heterogeneous team
    /// of specialists when several providers are connected); it defaults to Claude-only
    /// so existing callers keep today's behavior.
    /// A text-to-IMAGE request ("crea una imagen…", "genera un logo…") — a single-model creative
    /// task, NOT a job for an orchestrator+workers team. Requires an image noun AND a create verb,
    /// and bails when the text is clearly about code (so "add image upload to the app" stays a
    /// normal coding task). Drives the advisor to recommend solo + point at image generation.
    static func isImageTask(_ task: String) -> Bool {
        let t = normalize(task)
        let noun = contains(t, ["imagen", "imágenes", "imagenes", "foto", "fotografía", "fotografia",
                                "ilustración", "ilustracion", "logo", "logotipo", "póster", "poster",
                                "wallpaper", "icono", "image", "picture", "photo", "illustration",
                                "artwork", "icon", "avatar", "render"])
        let verb = contains(t, ["crea", "crear", "genera", "generar", "haz", "hazme", "dibuja",
                                "diseña", "diseñar", "make", "create", "generate", "draw", "design",
                                "paint", "render"])
        let codey = contains(t, ["código", "codigo", "code", "función", "funcion", "function", "feature",
                                 "componente", "component", "endpoint", "app ", "bug", "test", "deploy",
                                 "refactor", "subir", "upload", "botón", "boton", "button", "pantalla",
                                 "screen", "página", "pagina", "formulario", "database", "base de datos"])
        return noun && verb && !codey
    }

    static func advise(task: String, connected: Set<AIProvider> = [.claude]) -> Advice {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalize(trimmed)

        var steps: [DecisionStep] = []
        func record(_ question: String, yes: Bool, answer: String, evidence: [String]) {
            steps.append(DecisionStep(id: steps.count, questionKey: question,
                                      answerIsYes: yes, answerKey: answer,
                                      evidenceKeys: Array(evidence.prefix(3))))
        }

        // Q1 — does it need more than a quick answer?
        var depthEvidence = fired(depthGroups, in: text)
        if trimmed.count > 140 { depthEvidence.append("advisor.ev.long") }
        let needsDepth = !depthEvidence.isEmpty
        record("advisor.q.depth", yes: needsDepth,
               answer: needsDepth ? "advisor.a.depth.yes" : "advisor.a.depth.no",
               evidence: depthEvidence)

        // Q2 / Q3 — pick the model on the branch taken.
        let model: ClaudeModel
        if needsDepth {
            var hardestEvidence = fired(hardestGroups, in: text)
            // "complex/complejo" only counts when paired with an explicitly large scope.
            if contains(text, ["complex", "complejo", "compleja"]),
               contains(text, ["entire", "whole", "large", "end to end", "todo el", "toda la", "gran ", "grande"]) {
                hardestEvidence.append("advisor.ev.complexScope")
            }
            let hardest = !hardestEvidence.isEmpty
            model = hardest ? .fable5 : .opus5
            record("advisor.q.hardest", yes: hardest,
                   answer: hardest ? "advisor.a.hardest.yes" : "advisor.a.hardest.no",
                   evidence: hardestEvidence)
        } else {
            let speedEvidence = fired(speedGroups, in: text)
            let speedy = !speedEvidence.isEmpty
            model = speedy ? .haiku45 : .sonnet5
            record("advisor.q.speed", yes: speedy,
                   answer: speedy ? "advisor.a.speed.yes" : "advisor.a.speed.no",
                   evidence: speedEvidence)
        }

        // Strategy — reuse the generator's shape heuristic, then adjust: a cheap,
        // fast model doesn't need a fleet, so heavy shapes collapse to solo /
        // executor+advisor. The adjustment is an explicit step in the path.
        var (shape, teamSize) = StrategyGenerator.heuristicShape(for: trimmed, connected: connected)
        var rationaleKey = "advisor.rationale.\(shapeKeySuffix(shape))"
        // A text-to-image request is a single-model job — never an orchestrator+workers team.
        if isImageTask(trimmed) {
            shape = .solo; teamSize = 1
            rationaleKey = "advisor.rationale.image"
        }
        let isCheapModel = (model == .haiku45 || model == .sonnet5)
        let isHeavyShape = !(shape == .solo || shape == .executorAdvisor)
        // Fan-out shapes are PARALLEL LABOR (many near-identical agents); structural
        // shapes (planner→reviewer, debate, sparring) earn their keep from the SHAPE,
        // not the fleet size. So a cheap model only collapses a fan-out — the structural
        // teams survive, which is what restores variety (design/review/debate tasks no
        // longer all fold into executor+advisor).
        let isFanoutShape = (shape == .orchestratorWorkers
                             || shape == .domainSpecialists
                             || shape == .researchFanout)
        // A serial root-cause hunt has nothing to hand off — the accumulated context
        // is the work. Forcing a team there buys nothing, so it collapses to a lean
        // executor+advisor. Unlike the cheap-model downgrade, the model tier is kept:
        // debugging is judgment-heavy and still wants a capable lead.
        let nonDelegableEvidence = fired(nonDelegableGroups, in: text)
        let isNonDelegable = !nonDelegableEvidence.isEmpty
        if isHeavyShape {
            if isNonDelegable {
                shape = .executorAdvisor
                teamSize = 1
                rationaleKey = "advisor.rationale.nondelegable"
                record("advisor.q.team", yes: false, answer: "advisor.a.team.no",
                       evidence: nonDelegableEvidence)
            } else if isCheapModel && isFanoutShape {
                shape = (model == .haiku45) ? .solo : .executorAdvisor
                teamSize = 1
                rationaleKey = "advisor.rationale.downgraded"
                record("advisor.q.team", yes: false, answer: "advisor.a.team.no",
                       evidence: ["advisor.ev.cheapModel"])
            } else {
                record("advisor.q.team", yes: true, answer: "advisor.a.team.yes", evidence: [])
            }
        }
        var strategy = StrategyGenerator.buildStrategy(shape: shape, teamSize: teamSize)
        // The orchestrator is the main session — it runs the recommended model,
        // so the launch command and the cost estimate reflect the advice.
        if let i = strategy.roles.firstIndex(where: { $0.isOrchestrator }) {
            strategy.roles[i].model = model
        }

        // Loop kind — verifiable goal beats schedule beats external trigger.
        let loopKind: LoopKind
        let loopEvidence: [String]
        if contains(text, goalLoopGroup.keywords) {
            loopKind = .goalBased; loopEvidence = [goalLoopGroup.evidenceKey]
        } else if contains(text, timeLoopGroup.keywords) {
            loopKind = .timeBased; loopEvidence = [timeLoopGroup.evidenceKey]
        } else if contains(text, eventLoopGroup.keywords) {
            loopKind = .proactive; loopEvidence = [eventLoopGroup.evidenceKey]
        } else {
            loopKind = .turnBased; loopEvidence = []
        }
        record("advisor.q.loop", yes: loopKind != .turnBased,
               answer: "advisor.a.loop.\(loopKind.rawValue)", evidence: loopEvidence)

        // Effort — model tier plus scope. Medium is the estimator's baseline.
        let effort: CostEffort
        switch model {
        case .haiku45: effort = .low
        case .sonnet5: effort = .medium
        case .opus5, .opus48: effort = (trimmed.count > 280 || depthEvidence.count >= 2) ? .high : .medium
        case .fable5:  effort = .high
        }

        return Advice(model: model,
                      strategy: strategy,
                      shapeRationaleKey: rationaleKey,
                      loopKind: loopKind,
                      effort: effort,
                      decisionPath: steps,
                      goalSuggestion: draftGoal(task: trimmed, normalized: text),
                      estimatedCost: CostEstimator.estimate(strategy, effort: effort))
    }

    /// Like `advise`, but UPGRADES the team shape with Apple's on-device model when
    /// available — free and private (no subscription tokens). The deterministic pass
    /// still provides the model tier, loop kind, effort, decision path and goal (so
    /// the visual "why" is intact); the AI only reshapes the team and supplies a
    /// one-line rationale. Falls back to `advise` on any error or when AI is off.
    static func adviseWithAI(task: String, connected: Set<AIProvider> = [.claude]) async -> Advice {
        let base = advise(task: task, connected: connected)
        // Don't let the AI reshape an image request into a team — it's a single-model job.
        guard StrategyGenerator.isAIAvailable, !isImageTask(task),
              !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
        let ai = await StrategyGenerator.generate(from: task, connected: connected)
        guard ai.usedAI else { return base }
        var s = ai.strategy
        // Keep the recommended model on the orchestrator (launch command + cost).
        if let i = s.roles.firstIndex(where: { $0.isOrchestrator }) { s.roles[i].model = base.model }
        return Advice(model: base.model,
                      strategy: s,
                      shapeRationaleKey: base.shapeRationaleKey,
                      loopKind: base.loopKind,
                      effort: base.effort,
                      decisionPath: base.decisionPath,
                      goalSuggestion: base.goalSuggestion,
                      estimatedCost: CostEstimator.estimate(s, effort: base.effort),
                      aiRationale: ai.aiRationale,
                      usedAI: true)
    }

    // MARK: - Tiered options (cheaper ↔ better results)

    /// One recommendation option at a cost/quality point.
    struct Tier: Identifiable, Hashable {
        let id: String          // "saver" | "balanced" | "max"
        let labelKey: String    // short name, e.g. "advisor.tier.balanced"
        let noteKey: String     // tradeoff, e.g. "cheaper & faster"
        let advice: Advice
    }

    /// Three options for the same task: a cheaper/faster one, the balanced
    /// recommendation (AI-shaped when available), and a max-quality one that spends
    /// more for better results. Same shape/loop/goal — they differ in model tier and
    /// team size, so the estimated cost tells the tradeoff honestly.
    static func adviseTiers(task: String, connected: Set<AIProvider> = [.claude],
                            deprioritize: Set<AIProvider> = [],
                            modelLocked: Set<AIProvider> = []) async -> [Tier] {
        // Image generation is one model — show a SINGLE "one model" option, never the
        // economy/recommended/max team ladder (which would re-inflate a fleet).
        if isImageTask(task) {
            let solo = advise(task: task, connected: connected)
            return [Tier(id: "balanced", labelKey: "advisor.tier.solo",
                         noteKey: "advisor.tier.solo.note", advice: solo)]
        }
        let balanced = await adviseWithAI(task: task, connected: connected)
        // FIVE stops on a smooth quality dial, always — a ramp of model tier + team size + effort
        // from cheapest to strongest, centred on the AI-shaped "balanced" recommendation. Each end
        // is two model tiers away so the ramp is legible; costs tell the tradeoff honestly.
        // (id "balanced" stays the mid default so existing selection logic is unchanged.)
        let mid = Tier(id: "balanced", labelKey: "advisor.tier.balanced",
                       noteKey: "advisor.tier.balanced.note", advice: balanced)
        let ramp: [(id: String, label: String, note: String, shift: Int, count: Int, effort: CostEffort)] = [
            ("econ",  "advisor.tier.econ",  "advisor.tier.econ.note",  -2, -2, .low),
            ("value", "advisor.tier.value", "advisor.tier.value.note", -1, -1, lower(balanced.effort)),
            ("high",  "advisor.tier.high",  "advisor.tier.high.note",  +1, +1, higher(balanced.effort)),
            ("max",   "advisor.tier.max",   "advisor.tier.max.note",   +2, +2, higher(balanced.effort)),
        ]
        var built = ramp.map {
            variant(of: balanced, shift: $0.shift, countDelta: $0.count, effort: $0.effort,
                    id: $0.id, labelKey: $0.label, noteKey: $0.note)
        }
        built.append(mid)
        // Order cheapest → strongest: econ · value · balanced · high · max.
        let order = ["econ", "value", "balanced", "high", "max"]
        var tiers = order.compactMap { id in built.first { $0.id == id } }
        // Cross-provider: bias each tier's providers (economy → cheap/fast, max → top capability).
        if Set(connected).count > 1 {
            tiers = tiers.map { t in
                let advice = applyingProviders(t.advice, connected: connected,
                                               bias: TierBias.from(tierID: t.id), deprioritize: deprioritize,
                                               modelLocked: modelLocked)
                return Tier(id: t.id, labelKey: t.labelKey, noteKey: t.noteKey, advice: advice)
            }
        }
        return tiers
    }

    /// Build a cost/quality variant of an advice: shift EVERY agent's model up/down a
    /// tier (so the whole team visibly changes), nudge the largest fan-out role's
    /// count, and re-estimate the cost.
    private static func variant(of base: Advice, shift: Int, countDelta: Int,
                                effort: CostEffort, id: String, labelKey: String, noteKey: String) -> Tier {
        var s = base.strategy
        for i in s.roles.indices { s.roles[i].model = shiftModel(s.roles[i].model, by: shift) }
        let subIdx = s.roles.indices.filter { !s.roles[$0].isOrchestrator }
        if let idx = subIdx.max(by: { s.roles[$0].count < s.roles[$1].count }) {
            s.roles[idx].count = max(1, min(6, s.roles[idx].count + countDelta))
        }
        let headModel = s.roles.first(where: { $0.isOrchestrator })?.model ?? shiftModel(base.model, by: shift)
        let advice = Advice(model: headModel, strategy: s, shapeRationaleKey: base.shapeRationaleKey,
                            loopKind: base.loopKind, effort: effort, decisionPath: base.decisionPath,
                            goalSuggestion: base.goalSuggestion,
                            estimatedCost: CostEstimator.estimate(s, effort: effort),
                            aiRationale: base.aiRationale, usedAI: base.usedAI)
        return Tier(id: id, labelKey: labelKey, noteKey: noteKey, advice: advice)
    }

    private static func shiftModel(_ m: ClaudeModel, by: Int) -> ClaudeModel {
        var r = m
        for _ in 0..<abs(by) { r = by < 0 ? downTier(r) : upTier(r) }
        return r
    }

    private static func downTier(_ m: ClaudeModel) -> ClaudeModel {
        switch m { case .fable5: return .opus5; case .opus5, .opus48: return .sonnet5
                   case .sonnet5: return .haiku45; case .haiku45: return .haiku45 }
    }
    private static func upTier(_ m: ClaudeModel) -> ClaudeModel {
        switch m { case .haiku45: return .sonnet5; case .sonnet5: return .opus5
                   case .opus5, .opus48: return .fable5; case .fable5: return .fable5 }
    }
    private static func lower(_ e: CostEffort) -> CostEffort {
        switch e { case .high: return .medium; case .medium: return .low; case .low: return .low }
    }
    private static func higher(_ e: CostEffort) -> CostEffort {
        switch e { case .low: return .medium; case .medium: return .high; case .high: return .high }
    }

    // MARK: - Helpers

    /// Lowercase, fold diacritics, strip light punctuation, collapse whitespace,
    /// and pad with spaces so word-boundary keywords like " cada " can match.
    private static func normalize(_ s: String) -> String {
        let folded = s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let stripped = String(folded.map { ",.;:!?¡¿()[]\"'".contains($0) ? " " : $0 })
        let collapsed = stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return " " + collapsed + " "
    }

    /// Evidence keys of every group with at least one keyword hit, in table order.
    private static func fired(_ groups: [SignalGroup], in text: String) -> [String] {
        groups.compactMap { group in
            group.keywords.contains(where: { text.contains($0) }) ? group.evidenceKey : nil
        }
    }

    private static func contains(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    /// Stable localization-key suffix per shape (mirrors AppModel.strategyKey).
    private static func shapeKeySuffix(_ shape: StrategyShape) -> String {
        switch shape {
        case .solo:                return "solo"
        case .executorAdvisor:     return "execadv"
        case .plannerReviewer:     return "planner"
        case .orchestratorWorkers: return "fanout"
        case .researchFanout:      return "research"
        case .debateConsensus:     return "debate"
        case .domainSpecialists:   return "domain"
        case .sparring:            return "sparring"
        case .scoutAct:            return "scout"
        case .triageRouter:        return "triage"
        case .rootCauseDebugging:  return "rootcause"
        case .pipeline:            return "pipeline"
        }
    }

    /// Draft a one-line verifiable goal from the task's own words (best effort).
    private static func draftGoal(task: String, normalized: String) -> String {
        let firstLine = task.split(whereSeparator: \.isNewline).first.map(String.init) ?? task
        // The task already states its own finish line ("hasta que…", "until…"):
        // reuse it verbatim — it IS the goal.
        if normalized.contains("hasta que") || normalized.contains("until") {
            return String(firstLine.prefix(140)).trimmingCharacters(in: .whitespaces)
        }
        let snippet = String(firstLine.prefix(80)).trimmingCharacters(in: .whitespaces)
        // A verifiable artifact is mentioned: attach an "until it passes" clause.
        if let marker = verifiableMarkers.first(where: { normalized.contains($0.keyword) }) {
            return "\(snippet) — until \(marker.goal)"
        }
        // Generic fallback: the task plus a completion criterion.
        return "\(snippet) — until the result is verified and complete"
    }
}
