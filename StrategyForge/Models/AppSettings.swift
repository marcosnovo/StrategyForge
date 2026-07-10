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
    /// UI language. `.system` follows the OS language.
    var language: AppLanguage
    /// How autonomously the chat may act on the repo.
    var chatAutonomy: ChatAutonomy
    /// Restored UI state: the last-selected chat and whether the activity panel was open.
    var lastSelectedConfigID: String?
    var showActivity: Bool

    init(
        defaultReposPath: String? = nil,
        defaultReposBookmark: Data? = nil,
        claudeBinary: String = "claude",
        language: AppLanguage = .system,
        chatAutonomy: ChatAutonomy = .acceptEdits,
        lastSelectedConfigID: String? = nil,
        showActivity: Bool = false
    ) {
        self.defaultReposPath = defaultReposPath
        self.defaultReposBookmark = defaultReposBookmark
        self.claudeBinary = claudeBinary
        self.language = language
        self.chatAutonomy = chatAutonomy
        self.lastSelectedConfigID = lastSelectedConfigID
        self.showActivity = showActivity
    }

    // Tolerant decoding so older saved data (without newer keys) still loads.
    private enum CodingKeys: String, CodingKey {
        case defaultReposPath, defaultReposBookmark, claudeBinary, language, chatAutonomy
        case lastSelectedConfigID, showActivity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultReposPath = try c.decodeIfPresent(String.self, forKey: .defaultReposPath)
        defaultReposBookmark = try c.decodeIfPresent(Data.self, forKey: .defaultReposBookmark)
        claudeBinary = try c.decodeIfPresent(String.self, forKey: .claudeBinary) ?? "claude"
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        chatAutonomy = try c.decodeIfPresent(ChatAutonomy.self, forKey: .chatAutonomy) ?? .acceptEdits
        lastSelectedConfigID = try c.decodeIfPresent(String.self, forKey: .lastSelectedConfigID)
        showActivity = try c.decodeIfPresent(Bool.self, forKey: .showActivity) ?? false
    }
}
