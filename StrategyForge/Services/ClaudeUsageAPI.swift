//
//  ClaudeUsageAPI.swift
//  StrategyForge
//
//  Fetches the account's REAL rate-limit percentages from Claude's own usage endpoint
//  — the exact "36% of your 5-hour window / 55% of your week" that Claude Code shows —
//  which local logs can't give (Anthropic publishes no cap). It reads the OAuth access
//  token Claude Code stores in the login Keychain (per config-dir: the service is
//  "Claude Code-credentials" or "Claude Code-credentials-<sha256(dir)[:8]>"), then calls
//  GET /api/oauth/usage with the claude-code User-Agent.
//
//  Best-effort and non-fatal: returns nil if there's no valid token or the request
//  fails. NOTE: this uses your own subscription OAuth token against an undocumented
//  endpoint; it's the same data Claude Code reads, but treat it as best-effort.
//

import Foundation
import Security

enum ClaudeUsageAPI {

    /// Real rate-limit utilization for the two headline windows. Codable so the last
    /// fetched value can be cached to disk and shown at a glance on the next launch
    /// (before — or without — a fresh, Keychain-touching fetch).
    struct Exact: Equatable, Sendable, Codable {
        var fiveHourPercent: Double
        var fiveHourResetsAt: Date?
        var weekPercent: Double
        var weekResetsAt: Date?
        var computedAt: Date
    }

    /// The freshest non-expired Claude OAuth access token from the Keychain. Claude Code
    /// stores it keyed by config-dir, so we check the dir the app runs from + the default.
    static func accessToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // File-first: Claude Code also writes its OAuth to a plain credentials file in the
        // config dir on some setups. Reading a file the user owns needs NO Keychain access,
        // so it never prompts — try it before the Keychain (which does prompt).
        let configDir = ClaudeRunner.resolveClaudeConfigDir() ?? "\(home)/.claude"
        for path in ["\(configDir)/.credentials.json", "\(home)/.claude/.credentials.json"] {
            if let data = FileManager.default.contents(atPath: path),
               let token = freshToken(from: data) { return token }
        }
        // Keychain: Claude Code stores the OAuth keyed by CONFIG-DIR (service
        // "Claude Code-credentials-<hash>"), and which item holds the currently-valid token
        // depends on how the CLI was last launched (Coral spawns it with its own config dir),
        // so guessing a hash misses it — the fresh token can sit under a hash we never compute.
        //
        // Prefer ONE batch read that returns attributes AND data for every generic-password
        // item at once — in the happy path that's a single Keychain prompt for all the
        // "Claude Code-credentials"* items (the old code looped a per-service data read and
        // prompted N times: the "me pidió las credenciales 8 veces" bug). BUT a match-all
        // query that includes item data can fail WHOLESALE when any item in the chain is
        // inaccessible (errSecAuthFailed / errSecInteractionNotAllowed), which returned nil
        // and left the Claude % blank. So fall back to a resilient path: list the Claude
        // services with an attributes-only query (never prompts), then read the FRESHEST
        // one's data first and stop at the first non-expired token.
        if let items = keychainItems(returnData: true),
           let token = freshestToken(in: items) { return token }
        return freshestKeychainTokenResilient()
    }

    /// A generic-password lookup for every item, optionally including secret data. Returns nil
    /// only when the query genuinely fails (not merely "no items").
    private static func keychainItems(returnData: Bool) -> [[String: Any]]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        if returnData { query[kSecReturnData as String] = true }
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? [[String: Any]]
    }

    /// The freshest non-expired Claude token among already-fetched items (each carrying data).
    private static func freshestToken(in items: [[String: Any]]) -> String? {
        items
            .compactMap { item -> (mod: Date, data: Data)? in
                guard let svc = item[kSecAttrService as String] as? String,
                      svc.hasPrefix("Claude Code-credentials"),
                      let data = item[kSecValueData as String] as? Data else { return nil }
                return ((item[kSecAttrModificationDate as String] as? Date) ?? .distantPast, data)
            }
            .sorted { $0.mod > $1.mod }
            .lazy.compactMap { freshToken(from: $0.data) }
            .first
    }

    /// Resilient fallback: list Claude services (attributes only → no prompt), then read data
    /// one item at a time, freshest first, stopping at the first non-expired token. A single
    /// inaccessible item can't sink the whole lookup here.
    private static func freshestKeychainTokenResilient() -> String? {
        guard let attrs = keychainItems(returnData: false) else { return nil }
        let services = attrs
            .compactMap { item -> (svc: String, mod: Date)? in
                guard let svc = item[kSecAttrService as String] as? String,
                      svc.hasPrefix("Claude Code-credentials") else { return nil }
                return (svc, (item[kSecAttrModificationDate as String] as? Date) ?? .distantPast)
            }
            .sorted { $0.mod > $1.mod }
        for s in services {
            if let data = itemData(service: s.svc), let token = freshToken(from: data) { return token }
        }
        return nil
    }

    /// The secret bytes of one specific credential service (a single, targeted read).
    private static func itemData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess ? (out as? Data) : nil
    }

    /// Parse a Claude Code credentials blob (`{"claudeAiOauth":{"accessToken","expiresAt"}}`)
    /// and return the access token only if it hasn't expired. Shared by the file + Keychain
    /// sources.
    private static func freshToken(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        let ms = (oauth["expiresAt"] as? Double) ?? Double((oauth["expiresAt"] as? Int) ?? 0)
        return Date(timeIntervalSince1970: ms / 1000) > Date() ? token : nil
    }

    /// Fetch the real percentages. nil on no token / network error / non-200.
    static func fetch() async -> Exact? {
        guard let token = accessToken(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/1.0.60 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> (Double, Date?)? {
            guard let w = obj[key] as? [String: Any], let u = w["utilization"] as? Double else { return nil }
            return (u, (w["resets_at"] as? String).flatMap(parseDate))
        }
        guard let five = window("five_hour"), let week = window("seven_day") else { return nil }
        return Exact(fiveHourPercent: five.0, fiveHourResetsAt: five.1,
                     weekPercent: week.0, weekResetsAt: week.1, computedAt: Date())
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // The endpoint uses 6-digit fractional seconds; strip them for the plain parser.
        let stripped = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: stripped)
    }
}
