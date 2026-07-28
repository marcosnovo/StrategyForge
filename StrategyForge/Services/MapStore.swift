//
//  MapStore.swift
//  StrategyForge
//
//  Persists code maps so they're not lost when you leave the Map section. It caches the
//  small `graph.json` (a few KB–MB — NOT the repo) under Application Support, plus an index
//  of recent maps. Reopening a saved map is then instant and FREE: it parses the cached
//  graph, no re-run, no tokens, and it works even if the repo (a managed GitHub clone) was
//  later purged. graph.html is cached too so "Interactive" still works offline.
//
//  This is the answer to "maps aren't saved" and "why keep a local copy just to read the
//  graph quickly without spending tokens": Coral keeps the graph, not the repo.
//

import Foundation

/// A remembered code map: enough metadata to list it + where its cached graph lives.
struct SavedMap: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case local, github }
    var id: String              // stable key (used as the cache subfolder name)
    var name: String            // repo folder / repo name
    var kind: Kind
    var subtitle: String        // github "owner/repo", or the local path
    var repoPath: String?       // working copy on disk, if still available (nil = graph-only)
    var createdAt: Date
    var updatedAt: Date
    var nodeCount: Int
    var edgeCount: Int
    var communityCount: Int
    var hasHTML: Bool
}

@MainActor
@Observable
final class MapStore {
    static let shared = MapStore()

    private(set) var maps: [SavedMap] = []
    private let dir: URL

    init(storeDirectory: URL = AppPaths.supportDirectory().appendingPathComponent("maps", isDirectory: true)) {
        dir = storeDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Keys / paths

    static func key(kind: SavedMap.Kind, subtitle: String) -> String {
        switch kind {
        case .github: return "gh-" + subtitle.replacingOccurrences(of: "/", with: "-")
        case .local:  return "local-" + fnv1a(subtitle)
        }
    }
    private func mapDir(_ id: String) -> URL { dir.appendingPathComponent(id, isDirectory: true) }
    func cachedGraphURL(_ map: SavedMap) -> URL { mapDir(map.id).appendingPathComponent("graph.json") }
    func cachedHTMLURL(_ map: SavedMap) -> URL? {
        let u = mapDir(map.id).appendingPathComponent("graph.html")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: - Record / load / delete

    /// Cache a freshly-built map (copies graph.json + graph.html out of the repo) and upsert
    /// it into the recent list, newest first.
    func record(repoURL: URL, graph: CodeGraph, kind: SavedMap.Kind, subtitle: String) {
        let id = Self.key(kind: kind, subtitle: subtitle)
        let fm = FileManager.default
        let out = repoURL.appendingPathComponent("graphify-out", isDirectory: true)
        let destDir = mapDir(id)
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        copy(out.appendingPathComponent("graph.json"), to: destDir.appendingPathComponent("graph.json"))
        let srcHTML = out.appendingPathComponent("graph.html")
        let hasHTML = fm.fileExists(atPath: srcHTML.path)
        if hasHTML { copy(srcHTML, to: destDir.appendingPathComponent("graph.html")) }

        let now = Date()
        let created = maps.first(where: { $0.id == id })?.createdAt ?? now
        let entry = SavedMap(id: id, name: repoURL.lastPathComponent, kind: kind, subtitle: subtitle,
                             repoPath: repoURL.path, createdAt: created, updatedAt: now,
                             nodeCount: graph.nodes.count, edgeCount: graph.edges.count,
                             communityCount: graph.communityCount, hasHTML: hasHTML)
        maps.removeAll { $0.id == id }
        maps.insert(entry, at: 0)
        if maps.count > 40 { maps = Array(maps.prefix(40)) }
        save()
    }

    /// Parse a saved map's cached graph — instant, no graphify run, no tokens.
    func loadGraph(_ map: SavedMap) -> CodeGraph? {
        guard let data = try? Data(contentsOf: cachedGraphURL(map)) else { return nil }
        return CodeGraph.parse(data)
    }

    func delete(_ map: SavedMap) {
        try? FileManager.default.removeItem(at: mapDir(map.id))
        maps.removeAll { $0.id == map.id }
        save()
    }

    // MARK: - Persistence

    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    private func save() {
        guard let data = try? JSONEncoder().encode(maps) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SavedMap].self, from: data) else { return }
        maps = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func copy(_ src: URL, to dst: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return }
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }

    /// Deterministic hash (stable across launches, unlike Swift's randomized hashValue) for
    /// keying local repos by path.
    private static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }
}
