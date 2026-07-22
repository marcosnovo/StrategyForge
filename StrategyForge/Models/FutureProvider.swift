//
//  FutureProvider.swift
//  StrategyForge
//
//  The roadmap of AI back-ends Coral doesn't run yet but plans to — surfaced in the
//  "Connections" list as a "Coming soon" group the user can UPVOTE to tell us which to
//  build next. It's honest by design: there's no backend, so a vote is saved locally
//  (in `AppSettings`, synced via the same CloudKit config path) and — only if the user
//  has opted into usage sharing — logged to the local telemetry JSONL the team reads.
//  No fake global counts are ever shown.
//
//  The catalog is hand-curated per release, exactly like `AIProvider`'s metadata. Each
//  candidate is a real 2026 coding model with a plausible path to Coral's model (spawn a
//  headless CLI the user logs into with their own subscription). Ordering is the ballot
//  order — the strongest fits lead (Kimi / GLM / Qwen: a cheap frontier model, the best
//  subscription drop-in, and the lowest-effort integration).
//

import SwiftUI

struct FutureProvider: Identifiable, Hashable {
    /// Stable slug — the vote key. Never renumber; votes persist against it.
    let id: String
    /// Brand name shown in the row title.
    let name: String
    /// L10n key for the one-line "why" subtitle.
    let taglineKey: String
    /// SF Symbol shown in a quiet reef circle (no brand art yet — deliberately calmer
    /// than a live `ProviderLogo` so "coming soon" reads without a badge).
    let icon: String
    /// A restrained brand-ish tint (rendered muted in the row).
    let tint: Color
    let category: Category

    enum Category: String, Hashable {
        case frontier       // near-frontier capability
        case workhorse      // cheap daily driver
        case openSource     // open-weights
        case local          // runs offline on the user's Mac
    }

    /// The curated ballot (edit per release). Order = display/vote order.
    static let all: [FutureProvider] = [
        FutureProvider(id: "kimi", name: "Kimi K3",
                       taglineKey: "future.kimi.tagline", icon: "moon.stars.fill",
                       tint: Color(red: 0.45, green: 0.40, blue: 0.92), category: .frontier),
        FutureProvider(id: "glm", name: "GLM · Zhipu",
                       taglineKey: "future.glm.tagline", icon: "cube.fill",
                       tint: Color(red: 0.20, green: 0.55, blue: 0.85), category: .workhorse),
        FutureProvider(id: "qwen", name: "Qwen Coder",
                       taglineKey: "future.qwen.tagline", icon: "curlybraces",
                       tint: Color(red: 0.55, green: 0.35, blue: 0.80), category: .openSource),
        FutureProvider(id: "deepseek", name: "DeepSeek",
                       taglineKey: "future.deepseek.tagline", icon: "chevron.left.forwardslash.chevron.right",
                       tint: Color(red: 0.24, green: 0.47, blue: 0.90), category: .workhorse),
        FutureProvider(id: "grok", name: "Grok · xAI",
                       taglineKey: "future.grok.tagline", icon: "bolt.fill",
                       tint: Color(red: 0.30, green: 0.32, blue: 0.36), category: .frontier),
        FutureProvider(id: "mistral", name: "Mistral · Codestral",
                       taglineKey: "future.mistral.tagline", icon: "wind",
                       tint: Color(red: 0.92, green: 0.50, blue: 0.20), category: .frontier),
        FutureProvider(id: "local", name: "Local models",
                       taglineKey: "future.local.tagline", icon: "desktopcomputer",
                       tint: Color(red: 0.30, green: 0.60, blue: 0.52), category: .local),
    ]
}
