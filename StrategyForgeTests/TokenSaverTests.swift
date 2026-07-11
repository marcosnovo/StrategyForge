//
//  TokenSaverTests.swift
//  StrategyForgeTests
//
//  Unit tests for the pure Token Saver engine: weight thresholds, tip priority
//  and dismissal, bilingual vague-draft detection, batching, model-overkill
//  guards, the CLAUDE.md line check, and determinism.
//

import Testing
import Foundation
@testable import StrategyForge

struct TokenSaverEngineTests {

    /// Signals builder with quiet defaults so each test states only what it probes.
    private func signals(messages: Int = 0, tokens: Int = 0,
                         lastUser: [String] = [], attached: Bool = false,
                         imageOrPDF: Bool = false, orchestrator: ClaudeModel? = nil,
                         draft: String = "") -> TokenSaverEngine.Signals {
        TokenSaverEngine.Signals(messageCount: messages, cumulativeTokens: tokens,
                                 lastUserMessages: lastUser, justAttachedFile: attached,
                                 attachmentIsImageOrPDF: imageOrPDF,
                                 orchestratorModel: orchestrator, draft: draft)
    }

    // MARK: - Context weight

    @Test func weightThresholds() {
        #expect(TokenSaverEngine.weight(forTokens: 0) == .light)
        #expect(TokenSaverEngine.weight(forTokens: 49_999) == .light)
        #expect(TokenSaverEngine.weight(forTokens: 50_000) == .medium)
        #expect(TokenSaverEngine.weight(forTokens: 149_999) == .medium)
        #expect(TokenSaverEngine.weight(forTokens: 150_000) == .heavy)
    }

    // MARK: - Tip priority

    @Test func attachmentBeatsSummarizeWhenBothFire() {
        // Long + heavy chat AND a fresh image attachment: the attachment tip is
        // the only one that's actionable RIGHT NOW, so it wins.
        let s = signals(messages: 20, tokens: 200_000, attached: true, imageOrPDF: true)
        #expect(TokenSaverEngine.tip(for: s, dismissed: [])?.kind == .convertAttachment)
    }

    @Test func summarizeFiresAtSixteenMessages() {
        #expect(TokenSaverEngine.tip(for: signals(messages: 16), dismissed: [])?.kind == .summarizeRestart)
        #expect(TokenSaverEngine.tip(for: signals(messages: 15), dismissed: []) == nil)
        // Heavy cumulative tokens trigger it even in a short chat.
        #expect(TokenSaverEngine.tip(for: signals(messages: 2, tokens: 150_000), dismissed: [])?.kind == .summarizeRestart)
    }

    @Test func dismissedTipsAreSkippedAndNextPrioritySurfaces() {
        let s = signals(messages: 24, attached: true, imageOrPDF: true)
        // All firing: attachment wins.
        #expect(TokenSaverEngine.tip(for: s, dismissed: [])?.kind == .convertAttachment)
        // Attachment dismissed: the summarize nudge surfaces.
        #expect(TokenSaverEngine.tip(for: s, dismissed: [.convertAttachment])?.kind == .summarizeRestart)
        // Summarize also dismissed at >= 24 messages: rotate to new-topic-new-chat.
        #expect(TokenSaverEngine.tip(for: s, dismissed: [.convertAttachment, .summarizeRestart])?.kind == .newTopicNewChat)
        // Everything dismissed: silence.
        #expect(TokenSaverEngine.tip(for: s, dismissed: Set(TokenSaverEngine.TipKind.allCases)) == nil)
    }

    // MARK: - Vague follow-ups (bilingual)

    @Test func vagueSpanishDraftPointsAtSection() {
        let s = signals(messages: 4, draft: "hazlo mejor")
        #expect(TokenSaverEngine.tip(for: s, dismissed: [])?.kind == .pointAtSection)
        // Diacritics fold: "mejóralo" matches the normalized "mejoralo".
        let accented = signals(messages: 4, draft: "mejóralo")
        #expect(TokenSaverEngine.tip(for: accented, dismissed: [])?.kind == .pointAtSection)
        // A specific, long draft is NOT vague even if it contains "again".
        let specific = signals(messages: 4,
                               draft: "Rewrite only the error-handling paragraph in section 3 again, keeping the rest untouched")
        #expect(TokenSaverEngine.tip(for: specific, dismissed: []) == nil)
    }

    // MARK: - Batching

    @Test func batchingDetectedForThreeShortMessages() {
        let s = signals(messages: 6,
                        lastUser: ["fix the typo", "now the header", "and the footer"])
        #expect(TokenSaverEngine.tip(for: s, dismissed: [])?.kind == .batchPrompts)
        // One long message in the trio breaks the pattern.
        let mixed = signals(messages: 6,
                            lastUser: ["fix the typo",
                                       String(repeating: "a detailed multi-part request ", count: 4),
                                       "and the footer"])
        #expect(TokenSaverEngine.tip(for: mixed, dismissed: []) == nil)
        // Too early in the chat (< 6 messages) stays silent.
        let early = signals(messages: 4, lastUser: ["one", "two", "three"])
        #expect(TokenSaverEngine.tip(for: early, dismissed: []) == nil)
    }

    // MARK: - Model overkill

    @Test func modelOverkillFiresOnTrivialShortAsk() {
        let s = signals(messages: 0, orchestrator: .opus48, draft: "what does this error mean?")
        #expect(TokenSaverEngine.tip(for: s, dismissed: [])?.kind == .modelOverkill)
        // A cheap orchestrator never gets the tip.
        let cheap = signals(messages: 0, orchestrator: .sonnet5, draft: "what does this error mean?")
        #expect(TokenSaverEngine.tip(for: cheap, dismissed: []) == nil)
    }

    @Test func modelOverkillDoesNotFireForMultiStepDraft() {
        // Multi-step / code-shaped words mark real work — Opus/Fable is justified.
        let s = signals(messages: 0, orchestrator: .fable5,
                        draft: "Refactor the payment flow and then add tests")
        #expect(TokenSaverEngine.tip(for: s, dismissed: []) == nil)
        // A long draft (>= 80 chars) is not trivial either.
        let long = signals(messages: 0, orchestrator: .opus48,
                           draft: String(repeating: "explain this ", count: 8))
        #expect(TokenSaverEngine.tip(for: long, dismissed: []) == nil)
        // And an ongoing chat (> 2 messages) is out of scope for this tip.
        let ongoing = signals(messages: 4, orchestrator: .opus48, draft: "what is a monad?")
        #expect(TokenSaverEngine.tip(for: ongoing, dismissed: []) == nil)
    }

    // MARK: - CLAUDE.md check

    @Test func claudeMdWarningThreshold() {
        #expect(TokenSaverEngine.claudeMdWarning(lineCount: 300) == nil)
        #expect(TokenSaverEngine.claudeMdWarning(lineCount: 301) == "saver.claudemd.warning")
        #expect(TokenSaverEngine.claudeMdWarning(lineCount: 0) == nil)
    }

    // MARK: - Determinism

    @Test func sameSignalsAlwaysProduceTheSameTip() {
        let s = signals(messages: 18, tokens: 120_000, lastUser: ["ok", "sí", "dale"],
                        orchestrator: .fable5, draft: "hazlo mejor")
        let first = TokenSaverEngine.tip(for: s, dismissed: [])
        let second = TokenSaverEngine.tip(for: s, dismissed: [])
        #expect(first == second)
        #expect(first?.kind == .summarizeRestart)   // priority is stable too
        // Tip metadata is stable: keys derive from the kind.
        #expect(first?.titleKey == "saver.tip.summarizeRestart.title")
        #expect(first?.bodyKey == "saver.tip.summarizeRestart.body")
        #expect(first?.actionKey == "saver.tip.summarizeRestart.action")
    }
}
