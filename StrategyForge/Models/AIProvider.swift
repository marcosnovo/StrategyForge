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

    /// Fallback binaries to try if the primary isn't found. Google RETIRED `gemini` (the Gemini
    /// CLI) in mid-2026 in favour of `agy` (the Antigravity CLI), so a migrated user only has
    /// `agy` — try it so Gemini keeps working. (Invocation flags are kept compatible; if a future
    /// agy release diverges, that surfaces as a normal CLI error rather than "not installed".)
    var alternativeBinaries: [String] {
        switch self {
        case .gemini: return ["agy"]
        case .claude, .openai: return []
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

    /// SF Symbol fallback (used in menus, where custom images don't render).
    var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .openai: return "circle.hexagonpath.fill"
        case .gemini: return "diamond.fill"
        }
    }

    /// Brand logo in the asset catalog, used by `ProviderLogo` for prominent spots.
    var logoAsset: String {
        switch self {
        case .claude: return "LogoClaude"
        case .openai: return "LogoOpenAI"
        case .gemini: return "LogoGemini"
        }
    }

    /// The OpenAI knot is monochrome → render as a tintable template; the Claude
    /// starburst and Gemini star are full-color marks shown as-is.
    var logoIsTemplate: Bool { self == .openai }

    /// Whether the app can actually *run* on this provider. All three now execute:
    /// Claude as the chat session, and Codex/Gemini as one-shot workers in a mixed
    /// team (and per-chat provider). So none is "coming soon" anymore.
    var isExecutable: Bool { true }

    /// Whether the sign-in must open a visible Terminal up front. Coral now drives ALL
    /// logins in a HIDDEN pseudo-terminal (Claude's `auth login`, Codex's localhost
    /// callback, and Gemini's first-run TUI, which it navigates + detects via the creds
    /// file). Terminal stays available only as the sheet's on-failure fallback, so this
    /// is false for every provider.
    var loginNeedsTerminal: Bool { false }

    /// Whether this provider's CLI streams structured file-edit / command events that
    /// Code Mode (diffs, terminal, git panel) can render. Only Claude Code does today;
    /// gating on this keeps the code workspace honest until Codex/Gemini catch up.
    var supportsCodeMode: Bool { self == .claude }

    /// The npm package the app installs to get this provider's CLI (login-based).
    var npmPackage: String {
        switch self {
        case .claude: return "@anthropic-ai/claude-code"
        case .openai: return "@openai/codex"
        case .gemini: return "@google/gemini-cli"
        }
    }

    /// Version this Coral release pins each CLI to, as a supply-chain guard: a bare
    /// `npm install -g <pkg>` resolves `@latest`, so a compromised newest publish would
    /// run on the user's machine with no gate. Pinning to a version we've vetted for a
    /// given Coral release closes that window. Empty string = unpinned (track latest);
    /// bump these per release once a new CLI version is vetted.
    static let pinnedCLIVersions: [AIProvider: String] = [
        .claude: "",
        .openai: "",
        .gemini: "",
    ]

    /// The exact `npm install -g` spec: the package, plus a pinned `@version` when this
    /// release vets one (see `pinnedCLIVersions`). Falls back to the bare package.
    var npmInstallSpec: String {
        let pin = (Self.pinnedCLIVersions[self] ?? "").trimmingCharacters(in: .whitespaces)
        return pin.isEmpty ? npmPackage : "\(npmPackage)@\(pin)"
    }

    /// The command that starts the provider's browser sign-in with the user's
    /// subscription account (run in Terminal so the OAuth flow completes normally).
    var loginCommand: String {
        switch self {
        case .claude: return "claude auth login --claudeai"   // dedicated login; prints a browser URL
        case .openai: return "codex login"
        case .gemini: return "gemini"          // first run signs in (full-screen TUI)
        }
    }

    /// Localization keys for the "how to connect" help.
    var connectHelpKey: String { "provider.\(rawValue).connect" }

    /// Whether the provider's CLI accepts a reasoning-effort override. Codex does
    /// (`-c model_reasoning_effort=…`) and it works even with a ChatGPT-account login.
    var supportsReasoningEffort: Bool { self == .openai }

    /// Reasoning-effort levels offered for `supportsReasoningEffort` providers.
    /// "" = leave it to the account/CLI default.
    static let reasoningEffortOptions = ["", "minimal", "low", "medium", "high"]

    /// Common subscription tiers per provider, for the manual plan picker (the CLIs
    /// don't expose the plan, so the user declares it). Kept current-ish; free text
    /// is always allowed via the picker's "Other".
    var planOptions: [String] {
        switch self {
        case .claude: return ["Free", "Pro", "Max 5×", "Max 20×", "Team", "Enterprise", "API"]
        case .openai: return ["Free", "Plus", "Pro", "Team", "Enterprise", "API"]
        case .gemini: return ["Free", "Google AI Pro", "Google AI Ultra", "API"]
        }
    }

    /// The models this provider exposes (tier-based; exact ids are resolved by the
    /// provider's own CLI/login, so these stay general on purpose).
    var models: [ProviderModel] {
        switch self {
        case .claude:
            return ClaudeModel.allCases.map {
                ProviderModel(id: $0.rawValue, displayName: $0.displayName, tierKey: $0.tierNameKey)
            }
        case .openai:
            // Codex CLI model slugs (passed as `codex exec --model <id>`) that a ChatGPT
            // (subscription) login supports. NOTE: `gpt-5-codex` is API-only — it errors on a
            // ChatGPT account ("not supported when using Codex with a ChatGPT account"), so it
            // is deliberately excluded. `codex` also accepts any custom slug via the role's
            // free-text model field. Catalog current as of Aug 2026 (GPT-5.5 is the ChatGPT
            // default; 5.6 Terra/Luna are the go-forward pair as 5.4 retires end of Aug 2026) —
            // refresh per release; OpenAI rotates these roughly monthly.
            return [
                ProviderModel(id: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", tierKey: "model.tier.expert"),
                ProviderModel(id: "gpt-5.5", displayName: "GPT-5.5", tierKey: "model.tier.expert"),
                ProviderModel(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna", tierKey: "model.tier.generalist"),
                ProviderModel(id: "gpt-5", displayName: "GPT-5", tierKey: "model.tier.generalist"),
                ProviderModel(id: "gpt-5-mini", displayName: "GPT-5 mini", tierKey: "model.tier.fast"),
            ]
        case .gemini:
            // Real Gemini CLI model ids (passed as `gemini -m <id>`). Catalog current as of
            // Aug 2026: Gemini 3 (Pro/Flash) is live in the CLI, the 2.5 family runs until its
            // Oct 2026 shutdown. Any other id works via the role's free-text model field.
            return [
                ProviderModel(id: "gemini-3-pro-preview", displayName: "Gemini 3 Pro", tierKey: "model.tier.expert"),
                ProviderModel(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash", tierKey: "model.tier.generalist"),
                ProviderModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", tierKey: "model.tier.expert"),
                ProviderModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", tierKey: "model.tier.generalist"),
                ProviderModel(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite", tierKey: "model.tier.fast"),
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

/// The provider's brand logo from the asset catalog, sized to `size`. Monochrome
/// marks (OpenAI) render as a template tinted by `templateTint` (default: primary
/// so it stays visible in both light and dark); color marks show as-is.
struct ProviderLogo: View {
    let provider: AIProvider
    var size: CGFloat = 16
    var templateTint: Color = .primary

    var body: some View {
        Image(provider.logoAsset)
            .resizable()
            .renderingMode(provider.logoIsTemplate ? .template : .original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(templateTint)
            .frame(width: size, height: size)
            .accessibilityLabel(provider.displayName)
    }
}

/// A provider's brand logo inside a white circle — a small, tappable avatar for
/// the chat header (Refil-style provider list). The circle clips any oversized
/// artwork and keeps every mark (incl. the monochrome OpenAI knot) legible on any
/// surface. The active provider gets a tinted ring.
struct ProviderAvatar: View {
    let provider: AIProvider
    var size: CGFloat = 24
    var active: Bool = false

    var body: some View {
        ProviderLogo(provider: provider, size: size * 0.58, templateTint: .black)
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(active ? provider.tint : Color.black.opacity(0.12),
                                           lineWidth: active ? 2 : 1))
            .shadow(color: .black.opacity(0.10), radius: active ? 3 : 1, y: 0.5)
            .accessibilityLabel(provider.displayName)
    }
}
