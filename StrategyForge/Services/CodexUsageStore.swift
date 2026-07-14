//
//  CodexUsageStore.swift
//  StrategyForge
//
//  Real OpenAI Codex usage read from its local session logs. Unlike Claude (which
//  publishes no cap, so we can only count tokens), the Codex CLI writes the SERVER'S
//  authoritative rate-limit percentage to disk on every turn — so we can show a true
//  "% of your plan used" with the exact reset time, no network and no API key.
//
//  Source: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl — lines whose
//  `payload.type == "token_count"` carry `rate_limits.primary/secondary`
//  ({used_percent, window_minutes, resets_at}) + `plan_type` and a token total.
//  The counters are account-wide, so the most recent event is the freshest state.
//  Requires App Sandbox OFF (reads the user's home dir). Tolerant parsing: unknown
//  or legacy lines are skipped, never fatal.
//

import Foundation

/// One rate-limit window (e.g. the 5-hour or weekly bucket) as Codex reports it.
struct CodexWindow: Equatable {
    /// The server's authoritative "% of this window used" (0…100).
    var usedPercent: Double
    /// The window length in minutes (e.g. 10080 = weekly, ~300 = the 5-hour bucket).
    var windowMinutes: Int
    var resetsAt: Date?

    /// A short human label for the window based on its length.
    var kindLabelKey: String {
        if windowMinutes >= 6 * 24 * 60 { return "usage.codex.window.week" }   // ≥ ~1 week
        if windowMinutes >= 24 * 60 { return "usage.codex.window.day" }
        return "usage.codex.window.5h"
    }
}

/// Aggregated Codex usage read from local session logs.
struct CodexUsage: Equatable {
    var planType: String?         // "plus" | "pro" | …
    var primary: CodexWindow?     // the tighter/primary limit
    var secondary: CodexWindow?   // the other window, when present
    var totalTokens: Int
    var lastActivity: Date?
    var computedAt: Date

    var hasData: Bool { primary != nil || totalTokens > 0 }

    static let empty = CodexUsage(planType: nil, primary: nil, secondary: nil,
                                  totalTokens: 0, lastActivity: nil, computedAt: .distantPast)
}

enum CodexUsageStore {

    // Minimal, tolerant shape — only what we render.
    private struct Line: Decodable {
        let timestamp: String?
        let payload: Payload?
        struct Payload: Decodable {
            let type: String?
            let info: Info?
            let rate_limits: RateLimits?
        }
        struct Info: Decodable { let total_token_usage: Tokens? }
        struct Tokens: Decodable { let total_tokens: Int? }
        struct RateLimits: Decodable {
            let primary: Window?
            let secondary: Window?
            let plan_type: String?
        }
        struct Window: Decodable {
            let used_percent: Double?
            let window_minutes: Int?
            let resets_at: Double?     // unix epoch seconds
        }
    }

    /// Scan the local Codex logs and return the freshest usage state. Runs
    /// synchronously — call off the main thread. `now` is injectable for testing.
    static func load(now: Date = Date()) -> CodexUsage? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }

        // Newest files first (the active session holds the latest account-wide state).
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return nil }
        var files: [(url: URL, mod: Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            files.append((url, mod))
        }
        files.sort { $0.mod > $1.mod }

        let decoder = JSONDecoder()
        // Look through the most recent files until one yields a token_count event.
        for file in files.prefix(40) {
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            var best: (line: Line, date: Date)?
            text.enumerateLines { raw, _ in
                guard raw.contains("token_count") else { return }
                guard let data = raw.data(using: .utf8),
                      let parsed = try? decoder.decode(Line.self, from: data),
                      parsed.payload?.type == "token_count" else { return }
                let d = parseDate(parsed.timestamp) ?? .distantPast
                if best == nil || d >= best!.date { best = (parsed, d) }
            }
            guard let hit = best else { continue }
            let rl = hit.line.payload?.rate_limits
            func window(_ w: Line.Window?) -> CodexWindow? {
                guard let w, let pct = w.used_percent, let mins = w.window_minutes else { return nil }
                return CodexWindow(usedPercent: pct, windowMinutes: mins,
                                   resetsAt: w.resets_at.map { Date(timeIntervalSince1970: $0) })
            }
            return CodexUsage(
                planType: rl?.plan_type,
                primary: window(rl?.primary),
                secondary: window(rl?.secondary),
                totalTokens: hit.line.payload?.info?.total_token_usage?.total_tokens ?? 0,
                lastActivity: hit.date == .distantPast ? nil : hit.date,
                computedAt: now)
        }
        return nil
    }
}
