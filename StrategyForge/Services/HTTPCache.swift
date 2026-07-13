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
            throw URLError(.init(rawValue: http.statusCode))
        } catch {
            if let cached { return cached.data }   // offline / transient → serve stale
            throw error
        }
    }
}
