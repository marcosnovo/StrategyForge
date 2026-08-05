//
//  UsageStore.swift
//  StrategyForge
//
//  Real provider usage (Claude + Codex token counts from local logs, and Claude's
//  authoritative rate-limit % from its usage endpoint). Extracted from AppModel as
//  phase 2 of the incremental breakup (#35). Self-contained — it reads the CLIs' local
//  logs / the Claude endpoint and owns its own cache; AppModel keeps thin forwarders.
//

import Foundation

@Observable
@MainActor
final class UsageStore {
    /// Aggregated Claude usage read from ~/.claude logs (nil until first refresh).
    var claudeUsage: UsageSummary?
    /// Real Codex usage (authoritative % + reset) read from ~/.codex logs.
    var codexUsage: CodexUsage?
    /// Real Claude rate-limit percentages from Claude's own usage endpoint (needs a
    /// valid login). nil when signed out or the request fails.
    var claudeExact: ClaudeUsageAPI.Exact?
    /// True while a usage refresh is in flight.
    var isRefreshingUsage = false

    /// Re-read usage from LOCAL LOGS only (Claude + Codex token counts) — no Keychain,
    /// so this is safe to call ambiently (activity panel, nav card) without triggering a
    /// login-Keychain password prompt. The exact rate-limit % (which needs the Claude
    /// Keychain token) is fetched separately, only on deliberate intent — see
    /// `refreshExactUsage()`. That's why the app no longer asks for the Keychain password
    /// on every launch.
    func refreshUsage(includeExact: Bool = false) async {
        isRefreshingUsage = true
        // Seed the exact rate-limit % from the last cached fetch so the rail / activity
        // panel show it at a glance immediately — no Keychain touch. A fresh fetch (on
        // deliberate intent) replaces it.
        if claudeExact == nil { claudeExact = Self.loadCachedExact() }
        async let claude = Task.detached(priority: .utility) { ClaudeUsageStore.load() }.value
        async let codex = Task.detached(priority: .utility) { CodexUsageStore.load() }.value
        claudeUsage = await claude
        codexUsage = await codex
        isRefreshingUsage = false
        if includeExact { await refreshExactUsage() }
    }

    /// UserDefaults key for the cached exact-usage snapshot.
    private static let exactCacheKey = "claude.exactUsage.cache.v1"

    /// The last fetched exact usage as a "last known" figure. We keep showing it for a
    /// generous window (14 days) so opening Usage always has SOMETHING to display without
    /// touching the Keychain — a fresh number is one ↻ tap away.
    private static func loadCachedExact() -> ClaudeUsageAPI.Exact? {
        guard let data = UserDefaults.standard.data(forKey: exactCacheKey),
              let exact = try? JSONDecoder().decode(ClaudeUsageAPI.Exact.self, from: data),
              Date().timeIntervalSince(exact.computedAt) < 14 * 86_400 else { return nil }
        return exact
    }

    /// Fetch Claude's authoritative rate-limit % from its usage endpoint. This reads the
    /// Claude Code login token from the Keychain, which PROMPTS for access — and on a debug
    /// build (ad-hoc signature) "Always Allow" doesn't stick, so it would prompt on every
    /// launch. To honour "don't ask unless I ask", the AUTO path (opening Usage, the nav card,
    /// the ambient rail pill) NEVER touches the Keychain: it only shows the last cached
    /// snapshot. The Keychain — and thus the prompt — is reached ONLY on an explicit `force`
    /// refresh (the ↻ button in Usage). A signed release build then persists "Always Allow"
    /// so even that asks just once.
    func refreshExactUsage(force: Bool = false) async {
        guard force else {
            // AUTO: show the last known figure from cache; do NOT read the Keychain.
            if claudeExact == nil { claudeExact = Self.loadCachedExact() }
            return
        }
        if let exact = await Task.detached(priority: .utility, operation: { await ClaudeUsageAPI.fetch() }).value {
            claudeExact = exact
            // Cache it so the next launch can show the % immediately, no Keychain touch.
            if let data = try? JSONEncoder().encode(exact) {
                UserDefaults.standard.set(data, forKey: Self.exactCacheKey)
            }
        }
    }
}
