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
}
