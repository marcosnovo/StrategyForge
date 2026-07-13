//
//  AdvisorEngine+Providers.swift
//  StrategyForge
//
//  The cross-provider brain: given a team the Advisor already recommends (all
//  Claude), reassign the best (provider, model) to each role — but ONLY among the
//  providers the user has actually connected. This is the differentiator no single
//  vendor CLI can offer: a Codex implementer with a Gemini researcher and a Claude
//  reviewer, chosen on purpose.
//
//  Two ideas drive it:
//   1) A capability profile per model (5 axes: reasoning, coding, breadth, speed).
//      Each role kind cares about one axis; we pick the connected model that maxes it.
//   2) Diversity by design: the Reviewer/Advisor is deliberately pushed onto a
//      DIFFERENT model family than the one writing the code, so a second opinion
//      comes from a different failure profile — impossible inside one vendor's CLI.
//
//  Pure and deterministic, like the base engine: the same inputs (task + connected
//  set + bias) always produce the same picks, so the decision is explainable and
//  unit-testable without mocks.
//

import Foundation

extension AdvisorEngine {

    // MARK: - Capability profile

    /// The axes a model can be strong on. A role picks the one that matters to it.
    enum Axis: Hashable {
        case reasoning   // leading, planning, judging
        case coding      // authoring and refactoring code
        case breadth     // large context / reading & researching widely
        case speed       // fast and cheap for parallel labor
    }

    /// How aggressively to trade cost for quality — mirrors the Advisor's tiers.
    enum TierBias: Hashable {
        case saver, balanced, max

        /// Map a tier id ("saver" | "balanced" | "max") to a bias.
        static func from(tierID: String) -> TierBias {
            switch tierID {
            case "saver": return .saver
            case "max":   return .max
            default:      return .balanced
            }
        }
    }

    /// A model's capability fingerprint, scored 1–5 per axis. The numbers are a
    /// deliberate, editable starting point (not dogma) — the run history from the
    /// Mission Reports is meant to tune them over time.
    struct ModelProfile: Hashable {
        let provider: AIProvider
        let modelID: String       // ClaudeModel.rawValue, or a ProviderModel.id
        let displayName: String
        let reasoning: Int
        let coding: Int
        let breadth: Int
        let speed: Int

        func value(_ axis: Axis) -> Int {
            switch axis {
            case .reasoning: return reasoning
            case .coding:    return coding
            case .breadth:   return breadth
            case .speed:     return speed
            }
        }
    }

    /// The catalog. Non-Claude `modelID`s must stay in sync with `AIProvider.models`
    /// (guarded by a unit test), since that's what the CLI actually receives.
    static let modelProfiles: [ModelProfile] = [
        // Claude
        ModelProfile(provider: .claude, modelID: ClaudeModel.opus48.rawValue,
                     displayName: ClaudeModel.opus48.displayName,
                     reasoning: 5, coding: 4, breadth: 4, speed: 2),
        ModelProfile(provider: .claude, modelID: ClaudeModel.fable5.rawValue,
                     displayName: ClaudeModel.fable5.displayName,
                     reasoning: 5, coding: 4, breadth: 4, speed: 1),
        ModelProfile(provider: .claude, modelID: ClaudeModel.sonnet5.rawValue,
                     displayName: ClaudeModel.sonnet5.displayName,
                     reasoning: 4, coding: 4, breadth: 3, speed: 3),
        ModelProfile(provider: .claude, modelID: ClaudeModel.haiku45.rawValue,
                     displayName: ClaudeModel.haiku45.displayName,
                     reasoning: 2, coding: 2, breadth: 2, speed: 5),
        // OpenAI / Codex
        ModelProfile(provider: .openai, modelID: "gpt-5-codex", displayName: "GPT-5 Codex",
                     reasoning: 4, coding: 5, breadth: 3, speed: 3),
        ModelProfile(provider: .openai, modelID: "gpt-5", displayName: "GPT-5",
                     reasoning: 4, coding: 4, breadth: 3, speed: 3),
        ModelProfile(provider: .openai, modelID: "gpt-5-mini", displayName: "GPT-5 mini",
                     reasoning: 2, coding: 3, breadth: 2, speed: 5),
        // Gemini
        ModelProfile(provider: .gemini, modelID: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro",
                     reasoning: 4, coding: 3, breadth: 5, speed: 3),
        ModelProfile(provider: .gemini, modelID: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
                     reasoning: 3, coding: 2, breadth: 5, speed: 5),
    ]

    // MARK: - Explained pick

    /// One role's cross-provider assignment, for the UI's "why" panel. The role and
    /// provider names are raw (the view formats them); `reasonKey` localizes the why.
    struct ProviderPick: Hashable {
        let roleName: String
        let roleKind: RoleKind
        let provider: AIProvider
        let modelDisplayName: String
        let reasonKey: String
    }

    // MARK: - Role → axis

    /// The axis a role kind optimizes for. Reviewers/advisors nominally want
    /// reasoning, but they're resolved separately (diversity beats raw score).
    static func primaryAxis(for kind: RoleKind) -> Axis {
        switch kind {
        case .orchestrator, .planner: return .reasoning
        case .worker, .specialist:    return .coding
        case .researcher:             return .breadth
        case .reviewer, .advisor:     return .reasoning
        }
    }

    private static func isReviewRole(_ kind: RoleKind) -> Bool {
        kind == .reviewer || kind == .advisor
    }

    private static func reasonKey(for axis: Axis) -> String {
        switch axis {
        case .reasoning: return "advisor.provider.reason.reasoning"
        case .coding:    return "advisor.provider.reason.coding"
        case .breadth:   return "advisor.provider.reason.breadth"
        case .speed:     return "advisor.provider.reason.speed"
        }
    }

    // MARK: - Assignment (pure)

    /// Reassign the best connected (provider, model) to each role in `strategy`.
    /// Returns the mutated strategy plus an ordered, explained list of picks.
    ///
    /// No-op (returns the strategy unchanged, no picks) unless at least TWO distinct
    /// providers are connected — so a Claude-only user sees exactly today's behavior.
    static func assignProviders(to strategy: Strategy,
                                connected: Set<AIProvider>,
                                bias: TierBias = .balanced) -> (strategy: Strategy, picks: [ProviderPick]) {
        var s = strategy
        let connectedSet = connected.isEmpty ? [AIProvider.claude] : connected
        let available = modelProfiles.filter { connectedSet.contains($0.provider) }
        guard Set(available.map(\.provider)).count > 1 else { return (s, []) }

        // Collect (roleIndex, pick) so the UI can show picks in role order.
        var ordered: [(index: Int, pick: ProviderPick)] = []
        var coderProvider: AIProvider?

        // Pass 1 — every non-review role by its primary axis.
        for i in s.roles.indices where !isReviewRole(s.roles[i].role) {
            let axis = primaryAxis(for: s.roles[i].role)
            guard let profile = best(from: available, axis: axis, bias: bias) else { continue }
            apply(profile, to: &s.roles[i])
            ordered.append((i, ProviderPick(roleName: s.roles[i].name, roleKind: s.roles[i].role,
                                            provider: profile.provider,
                                            modelDisplayName: profile.displayName,
                                            reasonKey: reasonKey(for: axis))))
            if (s.roles[i].role == .worker || s.roles[i].role == .specialist), coderProvider == nil {
                coderProvider = profile.provider
            }
        }
        // No dedicated coder → the orchestrator is who "writes", so use its family.
        if coderProvider == nil {
            coderProvider = s.roles.first(where: { $0.isOrchestrator })?.provider
        }

        // Pass 2 — review roles: prefer a DIFFERENT family than the coder (diversity).
        for i in s.roles.indices where isReviewRole(s.roles[i].role) {
            let crossFamily = available.filter { $0.provider != coderProvider }
            let pool = crossFamily.isEmpty ? available : crossFamily
            guard let profile = best(from: pool, axis: .reasoning, bias: bias) else { continue }
            apply(profile, to: &s.roles[i])
            let reason = crossFamily.isEmpty
                ? "advisor.provider.reason.onlyOne"
                : "advisor.provider.reason.diversity"
            ordered.append((i, ProviderPick(roleName: s.roles[i].name, roleKind: s.roles[i].role,
                                            provider: profile.provider,
                                            modelDisplayName: profile.displayName,
                                            reasonKey: reason)))
        }

        let picks = ordered.sorted { $0.index < $1.index }.map(\.pick)
        return (s, picks)
    }

    // MARK: - Scoring (deterministic)

    /// The best profile for an axis under a bias, with a stable, deterministic
    /// tie-break (provider order, then model id) so the same inputs never reorder.
    private static func best(from candidates: [ModelProfile], axis: Axis, bias: TierBias) -> ModelProfile? {
        candidates.max { a, b in
            let sa = score(a, axis: axis, bias: bias)
            let sb = score(b, axis: axis, bias: bias)
            if sa != sb { return sa < sb }
            let oa = providerOrder(a.provider), ob = providerOrder(b.provider)
            if oa != ob { return oa > ob }               // lower order wins
            return a.modelID > b.modelID                  // then lexicographic
        }
    }

    /// Weighted score: the priority axis dominates (×100); the bias nudges the
    /// tie-break toward cheap/fast (saver) or top capability (max).
    private static func score(_ p: ModelProfile, axis: Axis, bias: TierBias) -> Int {
        let base = p.value(axis) * 100
        switch bias {
        case .saver:    return base + p.speed * 10
        case .balanced: return base + p.speed * 2 + p.reasoning * 2
        case .max:      return base + (p.reasoning + p.coding) * 10
        }
    }

    private static func providerOrder(_ p: AIProvider) -> Int {
        AIProvider.allCases.firstIndex(of: p) ?? Int.max
    }

    /// Write a profile onto a role, honoring the Claude vs non-Claude split the
    /// model uses (Claude → `model`; others → `providerModelID`).
    private static func apply(_ p: ModelProfile, to role: inout AgentRole) {
        role.provider = p.provider
        if p.provider == .claude {
            role.model = ClaudeModel(rawValue: p.modelID) ?? role.model
            role.providerModelID = nil
        } else {
            role.providerModelID = p.modelID
        }
    }

    // MARK: - Public entry points

    /// Provider-aware advice: the full base recommendation (model tier, loop, effort,
    /// decision path, goal) with each role reassigned to the best connected provider.
    /// Falls back to exactly the Claude-only advice when fewer than two providers are
    /// connected.
    static func adviseCrossProvider(task: String,
                                    connected: Set<AIProvider>,
                                    bias: TierBias = .balanced) async -> Advice {
        let base = await adviseWithAI(task: task)
        return applyingProviders(base, connected: connected, bias: bias)
    }

    /// Reassign providers on top of an already-built advice (used by `adviseTiers`,
    /// where each cost/quality tier gets its own bias). Internal so the main-file
    /// tier logic can reuse it.
    static func applyingProviders(_ advice: Advice,
                                  connected: Set<AIProvider>,
                                  bias: TierBias) -> Advice {
        let (s, picks) = assignProviders(to: advice.strategy, connected: connected, bias: bias)
        // The launch command's headline model tracks the orchestrator only while it
        // stays on Claude (the session model is a Claude Code concept).
        let head: ClaudeModel = (s.orchestrator?.provider == .claude ? (s.orchestrator?.model ?? advice.model) : advice.model)
        return Advice(model: head,
                      strategy: s,
                      shapeRationaleKey: advice.shapeRationaleKey,
                      loopKind: advice.loopKind,
                      effort: advice.effort,
                      decisionPath: advice.decisionPath,
                      goalSuggestion: advice.goalSuggestion,
                      estimatedCost: CostEstimator.estimate(s, effort: advice.effort),
                      aiRationale: advice.aiRationale,
                      usedAI: advice.usedAI,
                      providerPicks: picks)
    }
}
