//
//  UpdateChecker.swift
//  StrategyForge
//
//  A dependency-free "is there a newer build?" check for the directly-distributed
//  (Developer ID, non-App-Store) app. It reads the project's GitHub Releases: the
//  latest release's tag is the version, its notes (body) are the per-version
//  changelog, and its first .dmg/.zip asset is the download. It does NOT auto-install
//  — it points the user at the download. (Full Sparkle-style delta auto-update is a
//  later step that needs EdDSA signing keys + a hosted appcast.)
//
//  The version comparison is pure and unit-tested; the network part is best-effort
//  and never blocks the app (any failure returns nil / empty).
//

import Foundation

enum UpdateChecker {

    /// The GitHub repo that publishes Coral's notarized releases. Each release's notes
    /// are that version's changelog; the download is the release's first .dmg/.zip asset
    /// (or the release page when none is attached).
    static var repo = "marcosnovo/StrategyForge"

    struct Update: Equatable {
        let version: String
        let url: URL          // the download asset, or the release page as a fallback
        let notes: String?    // this version's changelog (markdown)
    }

    /// One published release, for the full changelog history view.
    struct Release: Equatable, Identifiable {
        let version: String
        let notes: String
        let url: URL
        let date: Date?
        var id: String { version }
    }

    /// This build's marketing version (CFBundleShortVersionString).
    static func currentVersion(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// The latest release, returned only when it's newer than `current`. nil when up to
    /// date or on any network error (the check is advisory and never an app error).
    static func check(current: String = currentVersion()) async -> Update? {
        guard let latest = await fetchLatest(),
              isVersion(current, olderThan: latest.version) else { return nil }
        return Update(version: latest.version, url: latest.url,
                      notes: latest.notes.isEmpty ? nil : latest.notes)
    }

    /// The most recent releases (newest first) for the changelog view.
    static func history(limit: Int = 20) async -> [Release] {
        guard let url = api("/releases?per_page=\(limit)"),
              let arr = await getJSONArray(url) else { return [] }
        return arr.compactMap(release(from:))
    }

    // MARK: - GitHub REST

    private static func fetchLatest() async -> Release? {
        // /releases/latest excludes drafts/prereleases; fall back to the list's newest.
        if let url = api("/releases/latest"),
           let obj = await getJSONObject(url),
           let r = release(from: obj) { return r }
        return await history(limit: 1).first
    }

    private static func release(from obj: [String: Any]) -> Release? {
        guard let tag = obj["tag_name"] as? String else { return nil }
        let version = normalize(tag)
        guard !version.isEmpty else { return nil }
        let notes = (obj["body"] as? String) ?? ""
        let assets = (obj["assets"] as? [[String: Any]]) ?? []
        let download = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") || $0.hasSuffix(".zip") || $0.hasSuffix(".pkg") }
        guard let urlStr = download ?? (obj["html_url"] as? String),
              let url = URL(string: urlStr) else { return nil }
        return Release(version: version, notes: notes, url: url,
                       date: (obj["published_at"] as? String).flatMap(parseDate))
    }

    private static func api(_ path: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)\(path)")
    }

    private static func getJSONObject(_ url: URL) async -> [String: Any]? {
        guard let data = await getData(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func getJSONArray(_ url: URL) async -> [[String: Any]]? {
        guard let data = await getData(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func getData(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Coral", forHTTPHeaderField: "User-Agent")   // GitHub requires a UA
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    private static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    private static func parseDate(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
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
