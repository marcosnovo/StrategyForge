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

    /// The last fetched exact usage, if it was cached recently enough to still be a
    /// useful "last known" figure (windows are 5h / weekly, so we cap staleness at 12h).
    private static func loadCachedExact() -> ClaudeUsageAPI.Exact? {
        guard let data = UserDefaults.standard.data(forKey: exactCacheKey),
              let exact = try? JSONDecoder().decode(ClaudeUsageAPI.Exact.self, from: data),
              Date().timeIntervalSince(exact.computedAt) < 12 * 3600 else { return nil }
        return exact
    }

    /// Whether we've already attempted the Keychain-backed exact-usage fetch this session
    /// — so a missing/expired token prompts (or no-ops) at most ONCE, never repeatedly.
    @ObservationIgnored private var didAttemptExactUsage = false

    /// How fresh a cached exact-usage snapshot must be for the AUTO path (opening Usage) to
    /// reuse it instead of touching the Keychain. The rate-limit windows are 5h/weekly, so a
    /// snapshot up to 3h old is still a useful figure — and reusing it means opening Usage
    /// never re-prompts for Keychain access once the first fetch has been granted.
    private static let exactAutoInterval: TimeInterval = 3 * 3600

    /// Fetch Claude's authoritative rate-limit % from its usage endpoint. This reads the
    /// Claude Code login token from the Keychain, which prompts for access the first time
    /// (and every time in a debug build, whose ad-hoc signature makes "Always Allow" not
    /// stick). So the AUTO path (opening Usage) reuses a fresh cached snapshot and does NOT
    /// touch the Keychain — the prompt happens only on the first-ever fetch or an explicit
    /// `force` refresh (the ↻ button). Once granted, the result is cached and shown for
    /// `exactAutoInterval` with no further prompts, across launches.
    func refreshExactUsage(force: Bool = false) async {
        if !force {
            // A fresh cached snapshot on hand → show it, skip the Keychain entirely.
            if let cached = claudeExact ?? Self.loadCachedExact(),
               Date().timeIntervalSince(cached.computedAt) < Self.exactAutoInterval {
                claudeExact = cached
                return
            }
            guard !didAttemptExactUsage else { return }
        }
        didAttemptExactUsage = true
        if let exact = await Task.detached(priority: .utility, operation: { await ClaudeUsageAPI.fetch() }).value {
            claudeExact = exact
            // Cache it so the next launch can show the % immediately, no Keychain touch.
            if let data = try? JSONEncoder().encode(exact) {
                UserDefaults.standard.set(data, forKey: Self.exactCacheKey)
            }
        }
    }
}
