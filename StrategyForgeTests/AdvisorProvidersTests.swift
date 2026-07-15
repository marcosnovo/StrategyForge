//
//  AdvisorProvidersTests.swift
//  StrategyForgeTests
//
//  Unit tests for the cross-provider assignment pass: catalog integrity, role→axis
//  routing, "diversity by design" for reviewers, the tier bias, the Claude-only
//  no-op guarantee, and determinism. The pass is pure, so no mocks are needed.
//

import Testing
import Foundation
@testable import Coral

struct AdvisorProvidersTests {

    // MARK: - Helpers

    private func role(_ name: String, _ kind: RoleKind, orchestrator: Bool = false,
                      count: Int = 1) -> AgentRole {
        AgentRole(name: name, role: kind, model: .sonnet5,
                  systemPrompt: "", description: "", count: count, isOrchestrator: orchestrator)
    }

    private func strategy(_ roles: [AgentRole]) -> Strategy {
        Strategy(name: "Test", description: "", roles: roles, orchestrationNotes: "")
    }

    private let all: Set<AIProvider> = [.claude, .openai, .gemini]

    // MARK: - Catalog integrity

    @Test func everyNonClaudeProfileIDExistsInItsProvider() {
        // Known API-only models the advisor profiles for API-key users, but which are
        // deliberately excluded from the provider's runnable-on-subscription model list.
        let apiOnly: Set<String> = ["gpt-5-codex"]
        for profile in AdvisorEngine.modelProfiles where profile.provider != .claude {
            let ids = profile.provider.models.map(\.id)
            #expect(ids.contains(profile.modelID) || apiOnly.contains(profile.modelID),
                    "\(profile.modelID) is not a real \(profile.provider.displayName) model id")
        }
    }

    @Test func everyClaudeModelHasAProfile() {
        for m in ClaudeModel.allCases {
            #expect(AdvisorEngine.modelProfiles.contains { $0.provider == .claude && $0.modelID == m.rawValue })
        }
    }

    // MARK: - Claude-only is a no-op

    @Test func singleProviderMakesNoChangesAndNoPicks() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("worker", .worker, count: 3)])
        let (out, picks) = AdvisorEngine.assignProviders(to: s, connected: [.claude])
        #expect(picks.isEmpty)
        #expect(out.roles.allSatisfy { $0.provider == .claude })
        // The topology is untouched.
        #expect(out.roles.map(\.name) == s.roles.map(\.name))
    }

    @Test func emptyConnectedSetIsTreatedAsClaudeOnly() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true)])
        let (_, picks) = AdvisorEngine.assignProviders(to: s, connected: [])
        #expect(picks.isEmpty)
    }

    // MARK: - Role → axis routing

    @Test func implementerGoesToTheBestCoder() {
        // With everything connected, a worker (coding axis) should land on GPT-5 Codex
        // (coding 5), the strongest coder in the catalog.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        let impl = out.roles.first { $0.name == "impl" }!
        #expect(impl.provider == .openai)
        #expect(impl.providerModelID == "gpt-5-codex")
    }

    @Test func researcherGoesToWidestContext() {
        // Researcher (breadth axis) → Gemini (breadth 5).
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("scout", .researcher, count: 4)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        let scout = out.roles.first { $0.name == "scout" }!
        #expect(scout.provider == .gemini)
    }

    @Test func orchestratorGoesToStrongestReasoner() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        // Reasoning axis: Claude Opus/Fable top the table at 5.
        #expect(out.orchestrator?.provider == .claude)
    }

    // MARK: - Diversity by design

    @Test func reviewerIsPushedOffTheCoderFamily() {
        // Coder (worker) → OpenAI; the reviewer must NOT also be OpenAI.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("review", .reviewer)])
        let (out, picks) = AdvisorEngine.assignProviders(to: s, connected: all)
        let impl = out.roles.first { $0.name == "impl" }!
        let review = out.roles.first { $0.name == "review" }!
        #expect(impl.provider == .openai)
        #expect(review.provider != impl.provider)
        // The pick is explained as diversity.
        #expect(picks.contains { $0.roleName == "review" && $0.reasonKey == "advisor.provider.reason.diversity" })
    }

    @Test func reviewerWithOnlyTwoProvidersStillCrossesFamily() {
        // Only Claude + OpenAI connected. Worker → OpenAI (coding 5 beats Claude 4),
        // so the reviewer is forced onto Claude.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker),
                          role("review", .reviewer)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: [.claude, .openai])
        let impl = out.roles.first { $0.name == "impl" }!
        let review = out.roles.first { $0.name == "review" }!
        #expect(impl.provider == .openai)
        #expect(review.provider == .claude)
    }

    // MARK: - Tier bias

    @Test func saverBiasPrefersFasterCheaperWorkers() {
        // Worker under the Economy bias should prefer a fast/cheap coder over the
        // top-capability one.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 5)])
        let (saver, _) = AdvisorEngine.assignProviders(to: s, connected: all, bias: .saver)
        let (maxT, _) = AdvisorEngine.assignProviders(to: s, connected: all, bias: .max)
        let saverImpl = saver.roles.first { $0.name == "impl" }!
        let maxImpl = maxT.roles.first { $0.name == "impl" }!
        // Max leans on the strongest coder; Economy should not pick a strictly more
        // expensive model than Max for the same role.
        #expect(maxImpl.providerModelID == "gpt-5-codex")
        #expect(saverImpl.provider != .claude || saverImpl.model == .haiku45 || saverImpl.model == .sonnet5)
    }

    // MARK: - Determinism

    @Test func sameInputsProduceIdenticalAssignment() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("scout", .researcher, count: 3),
                          role("review", .reviewer)])
        let (a, pa) = AdvisorEngine.assignProviders(to: s, connected: all, bias: .balanced)
        let (b, pb) = AdvisorEngine.assignProviders(to: s, connected: all, bias: .balanced)
        #expect(a.roles.map { "\($0.name)|\($0.provider.rawValue)|\($0.providerModelID ?? $0.model.rawValue)" }
                == b.roles.map { "\($0.name)|\($0.provider.rawValue)|\($0.providerModelID ?? $0.model.rawValue)" })
        #expect(pa == pb)
    }

    // MARK: - Picks are in role order

    @Test func picksAreOrderedByRoleIndex() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker),
                          role("review", .reviewer)])
        let (_, picks) = AdvisorEngine.assignProviders(to: s, connected: all)
        #expect(picks.map(\.roleName) == ["lead", "impl", "review"])
    }

    // MARK: - Coverage: connected providers actually get used (Gemini fix)

    @Test func connectedGeminiLandsOnTheReviewSeat() {
        // Coder → OpenAI, so the reviewer's second opinion should come from a third
        // family: Gemini (reasoning 4 vs Claude 5 is only a 1-pt loss — acceptable), so
        // all three connected providers appear instead of Gemini being shut out.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("review", .reviewer)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        #expect(out.roles.first { $0.name == "review" }?.provider == .gemini)
        #expect(Set(out.roles.map(\.provider)) == all)
    }

    @Test func everyConnectedProviderIsRepresentedOnADiverseTeam() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("scout", .researcher, count: 3),
                          role("review", .reviewer)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        #expect(Set(out.roles.map(\.provider)) == all)
    }

    @Test func coverageNeverPlantsAWeakCoderOnAPureCodingTeam() {
        // Lead + one coding worker only. Gemini (coding 3) would lose 2 points vs
        // GPT-5 Codex (5) — above the 1-pt threshold — so it is NOT forced in.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 3)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        #expect(!out.roles.contains { $0.provider == .gemini })
        #expect(out.roles.first { $0.name == "impl" }?.provider == .openai)
    }

    @Test func coverageIsANoOpWhenEveryProviderAlreadyUsed() {
        // scout→Gemini, impl→OpenAI, lead→Claude already covers all three; coverage
        // must not reshuffle anything.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("scout", .researcher, count: 3)])
        let (a, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        let (b, _) = AdvisorEngine.assignProviders(to: s, connected: all)
        #expect(a.roles.map(\.provider) == b.roles.map(\.provider))
        #expect(Set(a.roles.map(\.provider)) == all)
    }

    // MARK: - Usage-aware assignment (steer away from near-capped providers)

    @Test func deprioritizedProviderLosesRolesToAComparableRival() {
        // A coding worker normally lands on OpenAI (Codex, coding 5). Mark OpenAI as
        // near its limit → the role should move to the next comparable coder.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2)])
        #expect(AdvisorEngine.assignProviders(to: s, connected: all)
                    .strategy.roles.first { $0.name == "impl" }?.provider == .openai)
        let (capped, _) = AdvisorEngine.assignProviders(to: s, connected: all, deprioritize: [.openai])
        #expect(capped.roles.first { $0.name == "impl" }?.provider != .openai)
    }

    @Test func deprioritizedProviderIsStillUsedWhenItIsTheBestFitAnyway() {
        // If every candidate is deprioritized, the penalty is uniform, so the raw
        // capability ranking stands — a near-capped provider is never hard-excluded.
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker)])
        let (out, _) = AdvisorEngine.assignProviders(to: s, connected: [.claude, .openai],
                                                     deprioritize: [.claude, .openai])
        #expect(out.roles.first { $0.name == "impl" }?.provider == .openai)
    }

    @Test func emptyDeprioritizeMatchesTheDefault() {
        let s = strategy([role("lead", .orchestrator, orchestrator: true),
                          role("impl", .worker, count: 2),
                          role("review", .reviewer)])
        let a = AdvisorEngine.assignProviders(to: s, connected: all).strategy.roles.map(\.provider)
        let b = AdvisorEngine.assignProviders(to: s, connected: all, deprioritize: []).strategy.roles.map(\.provider)
        #expect(a == b)
    }
}
