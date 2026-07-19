//
//  SecurityScopedBookmark.swift
//  StrategyForge
//
//  Shared resolution for security-scoped folder bookmarks. AppModel and LoopStore both
//  resolve user-picked repo folders from bookmark data; this collapses the two identical
//  (and both stale-ignoring) copies into one place that ALSO regenerates a stale bookmark
//  so repo access keeps working across launches instead of silently rotting.
//

import Foundation

enum SecurityScopedBookmark {
    /// A resolved bookmark: the URL, plus fresh bookmark data when the system reported the
    /// original stale (nil when it was still current). Callers persist `refreshedData` so
    /// the next launch resolves cleanly.
    struct Resolved {
        let url: URL
        let refreshedData: Data?
    }

    /// Resolve security-scoped bookmark `data`. A stale bookmark still resolves once, but
    /// rots over time (macOS updates, folder moves) — when stale, regenerate fresh data
    /// from the resolved URL (inside a scoped-access window) so the caller can store it.
    static func resolve(_ data: Data) -> Resolved? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        guard stale else { return Resolved(url: url, refreshedData: nil) }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let fresh = try? url.bookmarkData(options: [.withSecurityScope],
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil)
        return Resolved(url: url, refreshedData: fresh)
    }
}
