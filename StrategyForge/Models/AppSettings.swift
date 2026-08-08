//
//  AppSettings.swift
//  StrategyForge
//
//  User settings: the default folder to look for repos and the path to the
//  `claude` binary used in launch commands.
//

import Foundation

/// How much the chat lets Claude Code act without asking. In headless mode there's
/// no way to approve prompts interactively, so the choice is made up front.
enum ChatAutonomy: String, Codable, CaseIterable, Identifiable {
    case acceptEdits   // auto-accept file edits (Write/Edit); shell still restricted
    case full          // bypass all permission checks (edits + shell + mkdir…)
    case plan          // read-only: Claude plans but doesn't modify anything

    var id: String { rawValue }
    /// The value passed to `claude --permission-mode`.
    var permissionMode: String {
        switch self {
        case .acceptEdits: return "acceptEdits"
        case .full: return "bypassPermissions"
        case .plan: return "plan"
        }
    }
    var labelKey: String { "autonomy.\(rawValue)" }
}

struct AppSettings: Codable, Hashable {
    /// Display path of the default folder where repos live (optional convenience).
    var defaultReposPath: String?
    /// Security-scoped bookmark for the default repos folder.
    var defaultReposBookmark: Data?
    /// The `claude` binary name or absolute path used in generated launch commands.
    var claudeBinary: String
    /// Binary name/paths for the other providers' CLIs (login-based, no API keys).
    var codexBinary: String
    var geminiBinary: String
    /// UI language. `.system` follows the OS language.
    var language: AppLanguage
    /// How autonomously the chat may act on the repo.
    var chatAutonomy: ChatAutonomy
    /// Restored UI state: the last-selected chat and whether the activity panel was open.
    var lastSelectedConfigID: String?
    /// The last team open in the Team section (device-local, like the chat above).
    var lastSelectedTeamID: String?
    var showActivity: Bool
    /// The user's self-declared subscription plan per provider (rawValue → label).
    /// No CLI exposes the plan, so this is entered by the user and shown in Usage /
    /// Connected Services for at-a-glance context.
    var providerPlans: [String: String]
    /// Codex reasoning effort ("" = account default; else minimal/low/medium/high).
    /// Works with a ChatGPT-account login (unlike model selection), passed to the
    /// CLI as `-c model_reasoning_effort`.
    var codexReasoningEffort: String
    /// When true, Codex runs via an OpenAI API key (stored in the Keychain, not here)
    /// which re-enables explicit model selection. Default false = subscription login.
    var openaiUseAPIKey: Bool
    /// Future-provider slugs the user has upvoted on the "Coming soon" roadmap (local
    /// only; no server). Rides along with the portable config's CloudKit sync so a vote
    /// isn't lost on the user's other Mac.
    var votedFutureProviders: Set<String>
    /// Free-text "request another provider" submissions, kept so the row can show a
    /// "Requested" confirmation (and, with telemetry on, they're logged for the team).
    var requestedProviders: [String]
    /// Optional webhook URL POSTed when a loop run finishes, so a finished/failed loop
    /// reaches you off the Mac (ntfy → phone, Slack/Discord channel, or any endpoint).
    /// Empty/nil = off. Kept here with the other local settings, not in the Keychain — a
    /// posting URL isn't a credential the way an API key is, and it never leaves this Mac
    /// except as the POST target the user chose.
    var loopWebhookURL: String?
    /// Providers pinned to the left rail's usage door — up to 3, so a multi-provider user can
    /// watch what matters in that tiny space without oversaturating it. Default: just Claude.
    var usageFavorites: [String]
    /// What a chat does with messages arriving from your OTHER chats (see PeerMessage).
    /// Defaults to `.hold`: a message from another chat starts a real turn that spends
    /// tokens and can touch the repo, so the first one asks before it lands. Set it to
    /// `.accept` once you trust the flow — unattended loops need `.accept` to react at all.
    var peerInbound: PeerInbound

    init(
        defaultReposPath: String? = nil,
        defaultReposBookmark: Data? = nil,
        claudeBinary: String = "claude",
        codexBinary: String = "codex",
        geminiBinary: String = "gemini",
        language: AppLanguage = .system,
        chatAutonomy: ChatAutonomy = .acceptEdits,
        lastSelectedConfigID: String? = nil,
        lastSelectedTeamID: String? = nil,
        showActivity: Bool = false,
        providerPlans: [String: String] = [:],
        codexReasoningEffort: String = "",
        openaiUseAPIKey: Bool = false,
        votedFutureProviders: Set<String> = [],
        requestedProviders: [String] = [],
        loopWebhookURL: String? = nil,
        usageFavorites: [String] = ["claude"],
        peerInbound: PeerInbound = .hold
    ) {
        self.defaultReposPath = defaultReposPath
        self.defaultReposBookmark = defaultReposBookmark
        self.claudeBinary = claudeBinary
        self.codexBinary = codexBinary
        self.geminiBinary = geminiBinary
        self.language = language
        self.chatAutonomy = chatAutonomy
        self.lastSelectedConfigID = lastSelectedConfigID
        self.lastSelectedTeamID = lastSelectedTeamID
        self.showActivity = showActivity
        self.providerPlans = providerPlans
        self.codexReasoningEffort = codexReasoningEffort
        self.openaiUseAPIKey = openaiUseAPIKey
        self.votedFutureProviders = votedFutureProviders
        self.requestedProviders = requestedProviders
        self.loopWebhookURL = loopWebhookURL
        self.usageFavorites = usageFavorites
        self.peerInbound = peerInbound
    }

    // Tolerant decoding so older saved data (without newer keys) still loads.
    private enum CodingKeys: String, CodingKey {
        case defaultReposPath, defaultReposBookmark, claudeBinary, codexBinary, geminiBinary
        case language, chatAutonomy, lastSelectedConfigID, lastSelectedTeamID, showActivity, providerPlans
        case codexReasoningEffort, openaiUseAPIKey
        case votedFutureProviders, requestedProviders
        case loopWebhookURL
        case usageFavorites
        case peerInbound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultReposPath = try c.decodeIfPresent(String.self, forKey: .defaultReposPath)
        defaultReposBookmark = try c.decodeIfPresent(Data.self, forKey: .defaultReposBookmark)
        claudeBinary = try c.decodeIfPresent(String.self, forKey: .claudeBinary) ?? "claude"
        codexBinary = try c.decodeIfPresent(String.self, forKey: .codexBinary) ?? "codex"
        geminiBinary = try c.decodeIfPresent(String.self, forKey: .geminiBinary) ?? "gemini"
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        chatAutonomy = try c.decodeIfPresent(ChatAutonomy.self, forKey: .chatAutonomy) ?? .acceptEdits
        lastSelectedConfigID = try c.decodeIfPresent(String.self, forKey: .lastSelectedConfigID)
        lastSelectedTeamID = try c.decodeIfPresent(String.self, forKey: .lastSelectedTeamID)
        showActivity = try c.decodeIfPresent(Bool.self, forKey: .showActivity) ?? false
        providerPlans = try c.decodeIfPresent([String: String].self, forKey: .providerPlans) ?? [:]
        codexReasoningEffort = try c.decodeIfPresent(String.self, forKey: .codexReasoningEffort) ?? ""
        openaiUseAPIKey = try c.decodeIfPresent(Bool.self, forKey: .openaiUseAPIKey) ?? false
        votedFutureProviders = try c.decodeIfPresent(Set<String>.self, forKey: .votedFutureProviders) ?? []
        requestedProviders = try c.decodeIfPresent([String].self, forKey: .requestedProviders) ?? []
        loopWebhookURL = try c.decodeIfPresent(String.self, forKey: .loopWebhookURL)
        usageFavorites = try c.decodeIfPresent([String].self, forKey: .usageFavorites) ?? ["claude"]
        peerInbound = try c.decodeIfPresent(PeerInbound.self, forKey: .peerInbound) ?? .hold
    }

    /// Providers pinned to the rail's usage door (mapped from stored raw values), capped at 3.
    var usageFavoriteProviders: [AIProvider] {
        usageFavorites.compactMap { AIProvider(rawValue: $0) }.prefix(3).map { $0 }
    }
    func isUsageFavorite(_ p: AIProvider) -> Bool { usageFavorites.contains(p.rawValue) }
    /// Toggle a provider as a usage favorite. Returns false (no-op) when trying to ADD a 4th.
    @discardableResult
    mutating func toggleUsageFavorite(_ p: AIProvider) -> Bool {
        if let i = usageFavorites.firstIndex(of: p.rawValue) { usageFavorites.remove(at: i); return true }
        guard usageFavorites.count < 3 else { return false }
        usageFavorites.append(p.rawValue)
        return true
    }

    /// The configured binary name/path for a provider.
    func binary(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return claudeBinary
        case .openai: return codexBinary
        case .gemini: return geminiBinary
        }
    }

    /// The user's declared plan for a provider (nil if not set).
    func plan(for provider: AIProvider) -> String? {
        let v = providerPlans[provider.rawValue]
        return (v?.isEmpty == false) ? v : nil
    }
    mutating func setPlan(_ plan: String?, for provider: AIProvider) {
        if let plan, !plan.isEmpty { providerPlans[provider.rawValue] = plan }
        else { providerPlans[provider.rawValue] = nil }
    }

    /// Whether the user has upvoted a future provider on the roadmap.
    func hasVotedFuture(_ id: String) -> Bool { votedFutureProviders.contains(id) }
    /// Toggle the user's vote for a future provider; returns the new voted state.
    @discardableResult
    mutating func toggleFutureVote(_ id: String) -> Bool {
        if votedFutureProviders.contains(id) { votedFutureProviders.remove(id); return false }
        votedFutureProviders.insert(id); return true
    }
}
