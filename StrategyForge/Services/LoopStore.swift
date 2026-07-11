//
//  LoopStore.swift
//  StrategyForge
//
//  Self-contained persistence for loops (independent of AppModel): the saved
//  LoopPlans, the current selection, and repo access via security-scoped
//  bookmarks. Persists to JSON in Application Support.
//

import Foundation
import SwiftUI
import AppKit

@Observable
@MainActor
final class LoopStore {

    static let shared = LoopStore()

    // MARK: - State

    var loops: [LoopPlan] = []
    var selectedLoopID: LoopPlan.ID?

    /// Live security-scoped URLs from this session's folder pickers, keyed by the
    /// owning plan id. A transient cache, not UI state — kept out of observation
    /// so resolving a bookmark during a view's body does not mutate observed
    /// state mid-render (same rationale as AppModel.liveRepoURLs).
    @ObservationIgnored
    private var liveRepoURLs: [LoopPlan.ID: URL] = [:]

    init() {
        load()
    }

    // MARK: - Selection / editing

    /// A stable two-way binding to a plan by id, for the editor. Nil when the
    /// plan no longer exists. The setter stamps `updatedAt` on real changes.
    func binding(_ id: LoopPlan.ID) -> Binding<LoopPlan>? {
        guard loops.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.loops.first(where: { $0.id == id }) ?? LoopPlan() },
            set: { newValue in
                guard let i = self.loops.firstIndex(where: { $0.id == id }) else { return }
                var stamped = newValue
                if self.loops[i] != newValue { stamped.updatedAt = Date() }
                self.loops[i] = stamped
            }
        )
    }

    // MARK: - Lifecycle

    /// Create (or adopt) a plan, select it, persist, and return its id.
    @discardableResult
    func addLoop(prefill: LoopPlan? = nil) -> LoopPlan.ID {
        let plan = prefill ?? LoopPlan()
        loops.insert(plan, at: 0)
        selectedLoopID = plan.id
        save()
        return plan.id
    }

    func delete(_ id: LoopPlan.ID) {
        loops.removeAll { $0.id == id }
        liveRepoURLs[id] = nil
        if selectedLoopID == id { selectedLoopID = loops.first?.id }
        save()
    }

    // MARK: - Repo selection

    /// Present an open panel to choose the target repo folder for a plan.
    /// Mirrors AppModel.pickRepo (security-scoped bookmark + live URL cache).
    func pickRepo(for id: LoopPlan.ID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose repository"
        panel.message = "Select the local repository where Coral will write the loop files."

        guard panel.runModal() == .OK, let url = panel.url,
              let i = loops.firstIndex(where: { $0.id == id }) else { return }

        loops[i].repoPath = url.path
        loops[i].repoBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        loops[i].updatedAt = Date()
        liveRepoURLs[id] = url
        save()
    }

    /// The repo URL for a plan: a live picked URL, else a resolved bookmark,
    /// else the raw path.
    func repoURL(for plan: LoopPlan) -> URL? {
        if let live = liveRepoURLs[plan.id] { return live }
        if let data = plan.repoBookmark, let url = resolveBookmark(data) {
            liveRepoURLs[plan.id] = url
            return url
        }
        if let path = plan.repoPath { return URL(fileURLWithPath: path) }
        return nil
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    // MARK: - Persistence (JSON in Application Support)

    /// Versioned wrapper with a tolerant decode, mirroring AppModel.PersistedState.
    private struct PersistedLoops: Codable {
        static let currentVersion = 1

        var schemaVersion: Int
        var loops: [LoopPlan]

        init(loops: [LoopPlan], schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.loops = loops
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, loops }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            loops = try c.decodeIfPresent([LoopPlan].self, forKey: .loops) ?? []
        }
    }

    private var storeURL: URL {
        AppPaths.supportDirectory().appendingPathComponent("loops.json")
    }

    /// Persist the store. Loops are small, so a synchronous atomic write keeps
    /// this simple; failures are silent by design (the next save retries).
    func save() {
        let state = PersistedLoops(loops: loops)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        let url = storeURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedLoops.self, from: data) else {
            // The store exists but can't be read. Starting empty is unavoidable,
            // but the next save() would overwrite the file — so preserve it first
            // (same corrupt-file backup behavior as AppModel.load()).
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("loops-corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return
        }
        loops = decoded.loops
        selectedLoopID = loops.first?.id
    }
}
