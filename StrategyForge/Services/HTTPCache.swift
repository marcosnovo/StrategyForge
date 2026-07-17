//
//  HTTPCache.swift
//  StrategyForge
//
//  A tiny on-disk HTTP cache for read-only catalog fetches (team catalog, skills).
//  It stores the last body + ETag per URL and revalidates with If-None-Match, so
//  10k users opening the catalog don't re-download it every time (a 304 is free) and
//  the catalog still works offline by falling back to the last good copy. No backend;
//  the cache lives in Application Support.
//

import Foundation
import CryptoKit

/// A real, typed cache error — vs fabricating a `URLError` from an HTTP status code
/// (which produces a bogus `URLError.Code`, since those are negative NSURLError values).
enum HTTPCacheError: Error, LocalizedError {
    case httpStatus(Int)
    var errorDescription: String? {
        switch self { case .httpStatus(let code): return "Request failed (HTTP \(code)) and no cached copy is available." }
    }
}

enum HTTPCache {

    /// A stable, filesystem-safe cache key for a URL (sha256 hex of the absolute URL).
    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct Entry: Codable {
        let etag: String?
        let data: Data
    }

    private static var dir: URL {
        let d = AppPaths.supportDirectory().appendingPathComponent("httpcache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func file(for url: URL) -> URL {
        dir.appendingPathComponent(cacheKey(for: url) + ".json")
    }

    private static func load(_ url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: file(for: url)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private static func store(_ entry: Entry, for url: URL) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: file(for: url), options: .atomic)
        purge()   // opportunistic — the dir is tiny (a few catalog entries)
    }

    /// Drop cache files older than `maxAge`, then trim oldest-first until under
    /// `maxTotalBytes`, so the cache can't grow without bound.
    static func purge(maxAge: TimeInterval = 30 * 24 * 3600, maxTotalBytes: Int = 25_000_000) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        let now = Date()
        var live: [(url: URL, date: Date, size: Int)] = []
        for u in items {
            let vals = try? u.resourceValues(forKeys: Set(keys))
            let date = vals?.contentModificationDate ?? .distantPast
            let size = vals?.fileSize ?? 0
            if now.timeIntervalSince(date) > maxAge { try? fm.removeItem(at: u); continue }
            live.append((u, date, size))
        }
        var total = live.reduce(0) { $0 + $1.size }
        guard total > maxTotalBytes else { return }
        for e in live.sorted(by: { $0.date < $1.date }) where total > maxTotalBytes {
            try? fm.removeItem(at: e.url); total -= e.size
        }
    }

    /// Fetch `url`, revalidating against the cached copy. Behavior:
    ///  - 304 Not Modified → the cached body (fast path; near-zero bandwidth).
    ///  - 200 → the fresh body, and the cache is updated with the new ETag.
    ///  - Any network failure → the last cached body if we have one, else rethrow.
    static func data(from url: URL, timeout: TimeInterval = 20) async throws -> Data {
        let cached = load(url)
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if let etag = cached?.etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return data }
            if http.statusCode == 304, let cached { return cached.data }
            if (200..<300).contains(http.statusCode) {
                let etag = http.value(forHTTPHeaderField: "ETag")
                store(Entry(etag: etag, data: data), for: url)
                return data
            }
            // A non-success status (e.g. 404): prefer a stale copy over an error.
            if let cached { return cached.data }
            throw HTTPCacheError.httpStatus(http.statusCode)
        } catch {
            if let cached { return cached.data }   // offline / transient → serve stale
            throw error
        }
    }
}
