//
//  AIProvider.swift
//  StrategyForge
//
//  The AI back-ends the app can run a chat on. Each maps to a headless CLI the
//  user logs into with their own subscription (no API keys): Claude Code (`claude`),
//  OpenAI Codex (`codex`, ChatGPT login) and Google Gemini (`gemini`, Google login).
//  Mixing providers *within one strategy* is a later phase; for now a chat runs on
//  one selected provider. Only Claude has a working execution engine today — the
//  others are detectable/connectable and their runners land once their CLIs are
//  present to verify against.
//

import SwiftUI

enum AIProvider: String, Codable, CaseIterable, Identifiable, Hashable {
    case claude
    case openai   // ChatGPT / Codex CLI
    case gemini   // Google Gemini CLI

    var id: String { rawValue }

    /// Human name shown in the UI.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "ChatGPT · Codex"
        case .gemini: return "Gemini"
        }
    }

    /// The CLI binary spawned headlessly for this provider.
    var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .openai: return "codex"
        case .gemini: return "gemini"
        }
    }

    /// A brand-ish tint for chips/badges (kept tasteful, not exact brand colors).
    var tint: Color {
        switch self {
        case .claude: return Theme.accent
        case .openai: return Color(red: 0.10, green: 0.72, blue: 0.60)   // teal-green
        case .gemini: return Color(red: 0.26, green: 0.52, blue: 0.96)   // blue
        }
    }

    var icon: String {
        switch self {
        case .claude: return "sparkle"
        case .openai: return "circle.hexagonpath"
        case .gemini: return "diamond"
        }
    }

    /// Whether the app can actually *run* a chat on this provider today.
    var isExecutable: Bool { self == .claude }

    /// The npm package the app installs to get this provider's CLI (login-based).
    var npmPackage: String {
        switch self {
        case .claude: return "@anthropic-ai/claude-code"
        case .openai: return "@openai/codex"
        case .gemini: return "@google/gemini-cli"
        }
    }

    /// The command that starts the provider's browser sign-in with the user's
    /// subscription account (run in Terminal so the OAuth flow completes normally).
    var loginCommand: String {
        switch self {
        case .claude: return "claude"          // first run signs in
        case .openai: return "codex login"
        case .gemini: return "gemini"          // first run signs in
        }
    }

    /// Localization keys for the "how to connect" help.
    var connectHelpKey: String { "provider.\(rawValue).connect" }

    /// The models this provider exposes (tier-based; exact ids are resolved by the
    /// provider's own CLI/login, so these stay general on purpose).
    var models: [ProviderModel] {
        switch self {
        case .claude:
            return ClaudeModel.allCases.map {
                ProviderModel(id: $0.rawValue, displayName: $0.displayName, tierKey: $0.tierNameKey)
            }
        case .openai:
            return [
                ProviderModel(id: "gpt-flagship", displayName: "GPT (flagship)", tierKey: "model.tier.expert"),
                ProviderModel(id: "gpt-mini", displayName: "GPT mini", tierKey: "model.tier.fast"),
            ]
        case .gemini:
            return [
                ProviderModel(id: "gemini-pro", displayName: "Gemini Pro", tierKey: "model.tier.generalist"),
                ProviderModel(id: "gemini-flash", displayName: "Gemini Flash", tierKey: "model.tier.fast"),
            ]
        }
    }
}

/// A selectable model within a provider. Kept provider-agnostic so the picker can
/// list any back-end's models uniformly.
struct ProviderModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Localization key for the capability tier (Expert / Generalist / Fast…).
    let tierKey: String
}
