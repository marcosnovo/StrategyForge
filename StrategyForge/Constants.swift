//
//  Constants.swift
//  StrategyForge
//
//  Single source of truth for values that change often: the catalog of Claude
//  models and the set of tools that Claude Code subagents can be granted.
//
//  IMPORTANT (Claude Code facts baked into this app):
//   • The ORCHESTRATOR's model is NOT a per-file setting. It is the model of the
//     main Claude Code session, chosen at launch (`claude --model <id>`) or with
//     `/model` inside the session. StrategyForge therefore treats it as a launch
//     setting and documents it in CLAUDE.md — never as agent frontmatter.
//   • WORKERS / secondary roles DO pin their model in the subagent's YAML
//     frontmatter (`model: <id>`).
//   • Single level of delegation: the orchestrator delegates to subagents; the
//     subagents never delegate further nor talk to each other.
//

import Foundation

/// Application-Support paths, with a one-time migration from the app's former
/// name. All persisted data (data.json, per-chat sessions, telemetry) lives under
/// a single folder, so moving that one folder migrates everything at once.
enum AppPaths {
    /// The app's data directory. Creates it and, on first access, migrates the
    /// legacy "StrategyForge" folder so existing users keep their chats and teams.
    static func supportDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Coral", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            let legacy = base.appendingPathComponent("StrategyForge", isDirectory: true)
            if fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: dir)   // brings sessions/ + telemetry along
            }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Namespace for app-wide constants. Kept centralized because model ids and the
/// available tool set evolve over time.
enum Constants {

    /// Bump when the model catalog or tool list is edited, so generated files can
    /// be traced back to a known configuration.
    static let toolsCatalogVersion = "2026.07"

    // MARK: - Claude models

    /// Static metadata describing a Claude model. The live enum used by the data
    /// model (`ClaudeModel`) is defined in Phase 1 and reads from this catalog.
    struct ModelInfo: Identifiable, Hashable {
        /// The exact model id passed to Claude Code (e.g. `claude-fable-5`).
        let id: String
        /// Human-friendly name shown in pickers.
        let displayName: String
        /// Optional localization KEY for a note surfaced as a tooltip (e.g.
        /// Fable's safeguard behavior). Resolve it through `AppModel.t(_:)` /
        /// `L10n` at render time so it follows the live language setting.
        let safeguardNoteKey: String?
    }

    /// The catalog of currently valid Claude models. Update here when Anthropic
    /// ships or renames models — everything else references these ids.
    static let models: [ModelInfo] = [
        ModelInfo(
            id: "claude-opus-4-8",
            displayName: "Opus 4.8",
            safeguardNoteKey: nil
        ),
        ModelInfo(
            id: "claude-fable-5",
            displayName: "Fable 5",
            safeguardNoteKey: "model.fable.safeguard"
        ),
        ModelInfo(
            id: "claude-sonnet-5",
            displayName: "Sonnet 5",
            safeguardNoteKey: nil
        ),
        ModelInfo(
            id: "claude-haiku-4-5",
            displayName: "Haiku 4.5",
            safeguardNoteKey: nil
        ),
    ]

    // MARK: - Claude Code tools

    /// The tools a Claude Code subagent can be granted in its `tools` frontmatter.
    /// If a subagent omits `tools`, it inherits all of them. Restricting tools is
    /// how we make, e.g., a reviewer read-only (`Read, Grep, Glob`).
    ///
    /// `Agent` (the delegation tool) is intentionally listed but should generally
    /// NOT be granted to subagents: Claude Code allows only a single level of
    /// delegation, so a worker with `Agent` would produce configs that don't do
    /// what they promise.
    static let availableTools: [String] = [
        "Read",
        "Write",
        "Edit",
        "Grep",
        "Glob",
        "Bash",
        "WebFetch",
        "WebSearch",
        "Agent",
    ]

    /// Tools that only read — the safe default set for reviewers, advisors and
    /// researchers, which must not modify the repository.
    static let readOnlyTools: [String] = ["Read", "Grep", "Glob"]

    // MARK: - Cost estimation (approximate)

    /// Approximate token pricing per model, USD per 1M tokens. These are estimates
    /// for a *relative* comparison between strategies, not a billing figure — keep
    /// them here so they're trivial to update as prices change. Fable 5's values
    /// are the published $10 in / $50 out; the rest follow the usual tier ordering.
    struct ModelPrice: Hashable {
        let inputPerM: Double
        let outputPerM: Double
    }

    static let pricing: [String: ModelPrice] = [
        "claude-opus-4-8":  ModelPrice(inputPerM: 15, outputPerM: 75),
        "claude-fable-5":   ModelPrice(inputPerM: 10, outputPerM: 50),
        "claude-sonnet-5":  ModelPrice(inputPerM: 3,  outputPerM: 15),
        "claude-haiku-4-5": ModelPrice(inputPerM: 1,  outputPerM: 5),
    ]

    // MARK: - Auth & sync

    /// Identity / sync configuration. Auth is strictly OPT-IN: the whole app works
    /// signed-out. Sign in with Apple needs no extra config; Google + CloudKit need
    /// the values below plus the matching capabilities enabled in Xcode signing.
    enum Auth {
        /// CloudKit private-database container. Enable the iCloud capability in
        /// Signing & Capabilities and select this container.
        static let iCloudContainer = "iCloud.com.marcosnovo.StrategyForge"

        /// Google OAuth 2.0 client ID (type: iOS/macOS). Create one at
        /// console.cloud.google.com → Credentials, then paste it here. Until it's
        /// a real value, the Google button surfaces a "not configured" message.
        static let googleClientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"

        /// Google requires the redirect URI to be the reversed client ID scheme.
        /// Also add this scheme under Info → URL Types.
        static var googleRedirectURI: String {
            let reversed = googleClientID
                .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            return "com.googleusercontent.apps.\(reversed):/oauth2redirect"
        }

        static var isGoogleConfigured: Bool {
            !googleClientID.hasPrefix("YOUR_GOOGLE_CLIENT_ID")
        }
    }
}
