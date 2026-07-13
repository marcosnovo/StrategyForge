//
//  Configuration.swift
//  StrategyForge
//
//  A saved configuration: a strategy paired with the repository it targets.
//  Persisted as JSON (Phase 5). The repo is stored as both a display path and a
//  security-scoped bookmark so access survives across launches in the sandbox.
//

import Foundation

struct Configuration: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var strategy: Strategy
    /// The AI back-end this chat runs on (Claude / ChatGPT·Codex / Gemini).
    var provider: AIProvider
    /// POSIX path of the target repo, for display. Nil until the user picks one.
    var repoPath: String?
    /// Security-scoped bookmark for the repo folder, so write access persists.
    var repoBookmark: Data?
    /// Last content change, used for last-writer-wins during sync. Stamped by
    /// AppModel.save() when the portable content actually changes.
    var updatedAt: Date
    /// When this configuration last wrote its files into the repo (nil = never).
    /// Device-local (like the repo binding); never synced.
    var lastGeneratedAt: Date?
    /// Last time the chat saw activity (created or messaged). Drives newest-first
    /// ordering in the sidebar. Device-local; never synced.
    var lastActiveAt: Date?
    /// The chat history for this configuration. Device-local — never synced (the
    /// portable projection excludes it), so conversations stay on this Mac.
    var transcript: [ChatMessage]
    /// True once the user renamed the chat, so auto-titling from the first message
    /// stops. Bookkeeping — not part of `hasSameContent`.
    var titleWasManuallySet: Bool
    /// True for a fresh chat whose team was NOT chosen by the user yet: the first
    /// message auto-recommends a strategy from the prompt. Cleared once the team is
    /// recommended or the user picks one. Bookkeeping — not part of `hasSameContent`.
    var strategyIsAuto: Bool
    /// Unsent chat input, preserved across chat switches / relaunches. Device-local.
    var draft: String
    /// Cumulative token usage + cost for this chat. Device-local.
    var totalTokens: Int
    var totalCostUSD: Double
    /// The chat this one continues from (set when a chat is summarized-and-restarted
    /// to save tokens), so the list can show the link. Device-local.
    var continuedFrom: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        strategy: Strategy,
        provider: AIProvider = .claude,
        repoPath: String? = nil,
        repoBookmark: Data? = nil,
        updatedAt: Date = .distantPast,
        lastGeneratedAt: Date? = nil,
        lastActiveAt: Date? = nil,
        transcript: [ChatMessage] = [],
        titleWasManuallySet: Bool = false,
        strategyIsAuto: Bool = false,
        draft: String = "",
        totalTokens: Int = 0,
        totalCostUSD: Double = 0,
        continuedFrom: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.provider = provider
        self.repoPath = repoPath
        self.repoBookmark = repoBookmark
        self.updatedAt = updatedAt
        self.lastGeneratedAt = lastGeneratedAt
        self.lastActiveAt = lastActiveAt
        self.transcript = transcript
        self.titleWasManuallySet = titleWasManuallySet
        self.strategyIsAuto = strategyIsAuto
        self.draft = draft
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.continuedFrom = continuedFrom
    }

    enum CodingKeys: String, CodingKey {
        case id, name, strategy, provider, repoPath, repoBookmark, updatedAt, lastGeneratedAt, lastActiveAt, transcript, titleWasManuallySet, strategyIsAuto, draft, totalTokens, totalCostUSD, continuedFrom
    }

    // Tolerant decode: files written before sync existed have no updatedAt.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        strategy = try c.decode(Strategy.self, forKey: .strategy)
        // Tolerate unknown provider rawValues from newer app versions — a throw
        // here would fail the whole store's decode (see AgentRole.init(from:)).
        let providerRaw = ((try? c.decodeIfPresent(String.self, forKey: .provider)) ?? nil) ?? ""
        provider = AIProvider(rawValue: providerRaw) ?? .claude
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath)
        repoBookmark = try c.decodeIfPresent(Data.self, forKey: .repoBookmark)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        lastGeneratedAt = try c.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        transcript = try c.decodeIfPresent([ChatMessage].self, forKey: .transcript) ?? []
        titleWasManuallySet = try c.decodeIfPresent(Bool.self, forKey: .titleWasManuallySet) ?? false
        // Existing chats (pre-flag) have already run, so default to NOT auto — we
        // must never silently re-pick the team of an established conversation.
        strategyIsAuto = try c.decodeIfPresent(Bool.self, forKey: .strategyIsAuto) ?? false
        draft = try c.decodeIfPresent(String.self, forKey: .draft) ?? ""
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        totalCostUSD = try c.decodeIfPresent(Double.self, forKey: .totalCostUSD) ?? 0
        continuedFrom = try c.decodeIfPresent(UUID.self, forKey: .continuedFrom)
    }

    /// True when the portable/user-visible content matches (ignores timestamps),
    /// so save() only bumps `updatedAt` on a real change.
    func hasSameContent(as other: Configuration) -> Bool {
        name == other.name
            && strategy == other.strategy
            && provider == other.provider
            && repoPath == other.repoPath
            && repoBookmark == other.repoBookmark
    }

    /// Ordering key for the sidebar: most recent activity (or last content change).
    var recency: Date { max(lastActiveAt ?? .distantPast, updatedAt) }

    /// A short subtitle for the sidebar (strategy + repo folder name).
    var subtitle: String {
        let folder = repoPath.map { ($0 as NSString).lastPathComponent } ?? "no repo"
        return "\(strategy.name) · \(folder)"
    }
}
