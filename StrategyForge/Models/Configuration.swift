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
    /// The chat history for this configuration. Device-local — never synced (the
    /// portable projection excludes it), so conversations stay on this Mac.
    var transcript: [ChatMessage]
    /// True once the user renamed the chat, so auto-titling from the first message
    /// stops. Bookkeeping — not part of `hasSameContent`.
    var titleWasManuallySet: Bool
    /// Unsent chat input, preserved across chat switches / relaunches. Device-local.
    var draft: String
    /// Cumulative token usage + cost for this chat. Device-local.
    var totalTokens: Int
    var totalCostUSD: Double

    init(
        id: UUID = UUID(),
        name: String,
        strategy: Strategy,
        provider: AIProvider = .claude,
        repoPath: String? = nil,
        repoBookmark: Data? = nil,
        updatedAt: Date = .distantPast,
        lastGeneratedAt: Date? = nil,
        transcript: [ChatMessage] = [],
        titleWasManuallySet: Bool = false,
        draft: String = "",
        totalTokens: Int = 0,
        totalCostUSD: Double = 0
    ) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.provider = provider
        self.repoPath = repoPath
        self.repoBookmark = repoBookmark
        self.updatedAt = updatedAt
        self.lastGeneratedAt = lastGeneratedAt
        self.transcript = transcript
        self.titleWasManuallySet = titleWasManuallySet
        self.draft = draft
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
    }

    enum CodingKeys: String, CodingKey {
        case id, name, strategy, provider, repoPath, repoBookmark, updatedAt, lastGeneratedAt, transcript, titleWasManuallySet, draft, totalTokens, totalCostUSD
    }

    // Tolerant decode: files written before sync existed have no updatedAt.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        strategy = try c.decode(Strategy.self, forKey: .strategy)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        repoPath = try c.decodeIfPresent(String.self, forKey: .repoPath)
        repoBookmark = try c.decodeIfPresent(Data.self, forKey: .repoBookmark)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        lastGeneratedAt = try c.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        transcript = try c.decodeIfPresent([ChatMessage].self, forKey: .transcript) ?? []
        titleWasManuallySet = try c.decodeIfPresent(Bool.self, forKey: .titleWasManuallySet) ?? false
        draft = try c.decodeIfPresent(String.self, forKey: .draft) ?? ""
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        totalCostUSD = try c.decodeIfPresent(Double.self, forKey: .totalCostUSD) ?? 0
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

    /// A short subtitle for the sidebar (strategy + repo folder name).
    var subtitle: String {
        let folder = repoPath.map { ($0 as NSString).lastPathComponent } ?? "no repo"
        return "\(strategy.name) · \(folder)"
    }
}
