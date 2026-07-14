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
import CryptoKit
import Security

enum ClaudeUsageAPI {

    /// Real rate-limit utilization for the two headline windows.
    struct Exact: Equatable, Sendable {
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
        func service(for dir: String) -> String {
            let hash = SHA256.hash(data: Data(dir.utf8)).map { String(format: "%02x", $0) }.joined()
            return "Claude Code-credentials-\(hash.prefix(8))"
        }
        // Ordered, most-likely first, and STOP at the first fresh token — each Keychain
        // item read triggers its own access prompt, so reading fewer = fewer prompts.
        var services = [service(for: ClaudeRunner.resolveClaudeConfigDir() ?? "\(home)/.claude"),
                        "Claude Code-credentials",
                        service(for: "\(home)/.claude")]
        var seen = Set<String>(); services = services.filter { seen.insert($0).inserted }
        for svc in services {
            guard let data = keychainData(service: svc),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else { continue }
            let ms = (oauth["expiresAt"] as? Double) ?? Double((oauth["expiresAt"] as? Int) ?? 0)
            if Date(timeIntervalSince1970: ms / 1000) > Date() { return token }
        }
        return nil
    }

    private static func keychainData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess ? (out as? Data) : nil
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
