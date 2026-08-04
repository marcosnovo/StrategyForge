//
//  TokenSaverEngine.swift
//  StrategyForge
//
//  The Token Saver's brain: a pure, deterministic heuristic engine that watches
//  cheap signals of the current chat and emits at most ONE actionable tip at a
//  time, plus a coarse "context weight" for the gauge pill. No UI, no I/O, no
//  network — the same Signals always produce the same Tip, so it is fully unit
//  testable (see TokenSaverTests).
//
//  The heuristics encode proven habits: Claude re-reads the ENTIRE conversation
//  on every message, so a 30-message session can burn ~232k tokens with ~98% of
//  the spend being re-reads. Everything below exists to break that curve early.
//
//  Matching is bilingual (EN + ES): drafts are lowercased and diacritics folded
//  ("mejóralo" → "mejoralo"), mirroring AdvisorEngine's normalization.
//

import Foundation

enum TokenSaverEngine {

    // MARK: - Context weight

    /// Coarse bucket for the cumulative context, driving the green/amber/red pill.
    enum ContextWeight: Hashable {
        case light    // < 50k cumulative tokens — a fresh-ish chat, nothing to do.
        case medium   // 50k ..< 150k — re-reads are getting expensive; watch it.
        case heavy    // >= 150k — every further message re-pays a heavy history.
    }

    /// Bucket the chat's cumulative tokens (thresholds documented on the cases).
    static func weight(forTokens tokens: Int) -> ContextWeight {
        if tokens >= 150_000 { return .heavy }
        if tokens >= 50_000 { return .medium }
        return .light
    }

    // MARK: - Tips

    /// The six habits the engine can nudge toward. Raw values feed the
    /// localization keys ("saver.tip.<kind>.title" / ".body" / ".action").
    enum TipKind: String, Hashable, CaseIterable {
        case summarizeRestart, convertAttachment, pointAtSection,
             batchPrompts, modelOverkill, newTopicNewChat
    }

    /// One actionable tip. Identity is the kind: at most one instance of each
    /// kind exists, so dismissal state is just a Set<TipKind>.
    struct Tip: Hashable, Identifiable {
        var id: TipKind { kind }
        let kind: TipKind
        let titleKey: String      // "saver.tip.<kind>.title"
        let bodyKey: String       // "saver.tip.<kind>.body"
        let actionKey: String?    // button label key; nil = informational only
        let icon: String          // SF Symbol
    }

    /// Everything the engine looks at — cheap values the chat already tracks.
    struct Signals: Hashable {
        var messageCount: Int = 0
        var cumulativeTokens: Int = 0
        /// Up to the last 3 USER messages, newest last (display text is fine).
        var lastUserMessages: [String] = []
        /// True only on the render right after an attachment was staged.
        var justAttachedFile: Bool = false
        var attachmentIsImageOrPDF: Bool = false
        var orchestratorModel: ClaudeModel? = nil
        /// The unsent composer text.
        var draft: String = ""
    }

    /// Pick the single most valuable tip for the current state, skipping any the
    /// user already dismissed. Priority: the biggest, most certain savings win.
    static func tip(for signals: Signals, dismissed: Set<TipKind>) -> Tip? {
        let draft = normalize(signals.draft)
        let draftLength = signals.draft.trimmingCharacters(in: .whitespacesAndNewlines).count

        // 1. An image/PDF was just staged — the one moment conversion is actionable.
        //    PDFs cost 1.5–3k tokens/page, uncropped screenshots ~1.3k; text is 10–20× cheaper.
        if !dismissed.contains(.convertAttachment),
           signals.justAttachedFile, signals.attachmentIsImageOrPDF {
            return make(.convertAttachment)
        }

        // 2. Long conversation = token furnace: a 30-message session ≈ 232k tokens,
        //    ~98% of it re-reading history. 16 messages / 150k tokens is the elbow.
        if !dismissed.contains(.summarizeRestart),
           signals.messageCount >= 16 || signals.cumulativeTokens >= 150_000 {
            return make(.summarizeRestart)
        }

        // 3. They sailed past the summarize nudge (>= 24 messages): rotate to the
        //    stronger framing — dead-weight context does nothing for new questions.
        if !dismissed.contains(.newTopicNewChat), signals.messageCount >= 24 {
            return make(.newTopicNewChat)
        }

        // 4. A short, vague redo ("hazlo mejor", "redo it") forces a FULL
        //    regeneration; pointing at the exact section costs only that part.
        //    Requires a prior assistant reply (>= 2 messages) to make sense.
        if !dismissed.contains(.pointAtSection),
           signals.messageCount >= 2, draftLength > 0, draftLength < 60,
           vagueRedoPhrases.contains(where: { draft.contains($0) }) {
            return make(.pointAtSection)
        }

        // 5. Three tiny prompts in a row = three full context reloads; one batched
        //    message would have cost a single reload.
        if !dismissed.contains(.batchPrompts),
           signals.messageCount >= 6,
           signals.lastUserMessages.count >= 3,
           signals.lastUserMessages.suffix(3).allSatisfy({
               let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
               return !t.isEmpty && t.count < 60
           }) {
            return make(.batchPrompts)
        }

        // 6. A trivial, short first ask on an Opus/Fable orchestrator: Sonnet or
        //    Haiku answers it at a fraction of the price (two clicks in Team).
        //    Any code-ish / multi-step word means real work — stay silent then.
        if !dismissed.contains(.modelOverkill),
           let orch = signals.orchestratorModel, orch == .opus5 || orch == .opus48 || orch == .fable5,
           signals.messageCount <= 2,
           (1..<80).contains(draftLength),
           !heavyWorkKeywords.contains(where: { draft.contains($0) }) {
            return make(.modelOverkill)
        }

        return nil
    }

    // MARK: - CLAUDE.md check

    /// Static check: CLAUDE.md beyond ~300 lines is re-read on EVERY session and
    /// degrades instruction-following. Returns the warning's localization key.
    static func claudeMdWarning(lineCount: Int) -> String? {
        lineCount > 300 ? "saver.claudemd.warning" : nil
    }

    // MARK: - Signal tables (pre-normalized: lowercase, no diacritics)

    /// Vague-redo phrases that trigger a full regeneration (EN + ES).
    private static let vagueRedoPhrases: [String] = [
        "redo", "again", "start over", "make it better", "improve it",
        "not like that", "try harder", "otra vez", "de nuevo", "hazlo mejor",
        "mejoralo", "rehazlo", "repitelo", "hazlo bien", "no me gusta", "asi no",
    ]

    /// Words that mark a draft as real (multi-step / code-shaped) work, where a
    /// top-tier orchestrator is justified (EN + ES).
    private static let heavyWorkKeywords: [String] = [
        "refactor", "implement", "implementa", "migrate", "migra", "debug",
        "depura", "audit", "audita", "architect", "arquitect", "test", "build",
        "construye", "compile", "compila", "deploy", "despliega", "code",
        "codigo", "api", "endpoint", "database", "base de datos",
        "step", "paso", "then", "luego", "despues", "first", "primero",
    ]

    // MARK: - Helpers

    /// Lowercase and fold diacritics so bilingual keywords match accent-free.
    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build the Tip for a kind — keys derive from the raw value; action and
    /// icon are the only per-kind metadata.
    private static func make(_ kind: TipKind) -> Tip {
        let action: String?
        let icon: String
        switch kind {
        case .summarizeRestart:  action = "saver.tip.summarizeRestart.action";  icon = "arrow.triangle.2.circlepath"
        case .convertAttachment: action = "saver.tip.convertAttachment.action"; icon = "doc.plaintext"
        case .pointAtSection:    action = nil;                                  icon = "scope"
        case .batchPrompts:      action = nil;                                  icon = "square.stack.3d.up"
        case .modelOverkill:     action = nil;                                  icon = "speedometer"
        case .newTopicNewChat:   action = "saver.tip.newTopicNewChat.action";   icon = "plus.bubble"
        }
        return Tip(kind: kind,
                   titleKey: "saver.tip.\(kind.rawValue).title",
                   bodyKey: "saver.tip.\(kind.rawValue).body",
                   actionKey: action,
                   icon: icon)
    }
}
