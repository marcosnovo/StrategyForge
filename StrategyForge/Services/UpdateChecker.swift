//
//  UpdateChecker.swift
//  StrategyForge
//
//  A dependency-free "is there a newer build?" check for the directly-distributed
//  (Developer ID, non-App-Store) app. It fetches a small static manifest JSON from a
//  URL you host on a CDN and compares its version to this build's. It does NOT
//  auto-install — it points the user at the download. (Full Sparkle-style delta
//  auto-update is a later step that needs EdDSA signing keys + a hosted appcast.)
//
//  The version comparison is pure and unit-tested; the network part is best-effort
//  and never blocks the app.
//

import Foundation

enum UpdateChecker {

    /// Where the version manifest lives. Empty by default → the check is dormant
    /// (returns nil) until you host a manifest and set this. Shape:
    /// { "version": "1.2.0", "url": "https://…/Coral-1.2.0.dmg", "notes": "…" }
    static var manifestURLString = ""

    struct Manifest: Codable {
        let version: String
        let url: String
        let notes: String?
    }

    struct Update: Equatable {
        let version: String
        let url: URL
        let notes: String?
    }

    /// This build's marketing version (CFBundleShortVersionString).
    static func currentVersion(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Fetch the manifest and return an Update when it's newer than `current`.
    /// Returns nil when up to date, unconfigured, or on any network error (the check
    /// is advisory and must never surface as an app error).
    static func check(current: String = currentVersion()) async -> Update? {
        guard let url = URL(string: manifestURLString), !manifestURLString.isEmpty else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let downloadURL = URL(string: manifest.url) else { return nil }
        guard isVersion(current, olderThan: manifest.version) else { return nil }
        return Update(version: manifest.version, url: downloadURL, notes: manifest.notes)
    }

    /// Pure dotted-version compare: true when `a` precedes `b` (e.g. "1.2.0" < "1.10").
    /// Non-numeric junk and unequal lengths are handled by zero-padding components.
    static func isVersion(_ a: String, olderThan b: String) -> Bool {
        let lhs = components(a), rhs = components(b)
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
