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

    /// Where loops.json lives — injectable so tests can use a scratch directory.
    @ObservationIgnored private let storeDirectory: URL
    /// The file-panel seam (FilePanelPresenting), injected like AppModel's so the
    /// repo-binding path is testable without a modal.
    @ObservationIgnored private let filePanels: FilePanelPresenting

    // MARK: - State

    var loops: [LoopPlan] = []
    var selectedLoopID: LoopPlan.ID?

    /// Live security-scoped URLs from this session's folder pickers, keyed by the
    /// owning plan id. A transient cache, not UI state — kept out of observation
    /// so resolving a bookmark during a view's body does not mutate observed
    /// state mid-render (same rationale as AppModel.liveRepoURLs).
    @ObservationIgnored
    private var liveRepoURLs: [LoopPlan.ID: URL] = [:]

    // MARK: - Run lifetime (store-owned controllers)

    /// One run controller per loop, owned here (not by the run panel) so a run
    /// survives navigating to another loop/section. Not observed: lazily filling
    /// this cache from a view body must not mutate observed state mid-render.
    @ObservationIgnored private var runControllers: [LoopPlan.ID: LoopRunController] = [:]
    /// Loops with a run in flight (observed — drives global running indicators).
    /// Mutated only from onRunningChanged callbacks (action context).
    var runningLoopIDs: Set<LoopPlan.ID> = []

    /// Source-chat ids of every loop currently running — so a chat row can show that a
    /// loop is running "over" it. Empty when nothing's running.
    var runningLoopSourceChatIDs: Set<UUID> {
        Set(loops.filter { runningLoopIDs.contains($0.id) }.compactMap(\.sourceChatID))
    }

    /// Is a loop from `chatID` currently running?
    func isLoopRunning(forChat chatID: UUID) -> Bool {
        loops.contains { $0.sourceChatID == chatID && runningLoopIDs.contains($0.id) }
    }

    /// Keep loops sourced from a chat labelled with its current name when it's renamed.
    func updateSourceName(forChat chatID: UUID, to name: String) {
        var changed = false
        for i in loops.indices where loops[i].sourceChatID == chatID && loops[i].sourceChatName != name {
            loops[i].sourceChatName = name
            changed = true
        }
        if changed { save() }
    }
    /// Error sink wired by the app shell: (localization key, %@ detail).
    @ObservationIgnored var onError: ((String, String) -> Void)?
    /// A corrupt-load error parked until the app shell can show it (load()
    /// runs before any banner surface exists).
    var loadError: (key: String, detail: String)?
    /// Called after a run finishes (any terminal state) with its summary.
    @ObservationIgnored var onRunFinished: ((LoopPlan.ID, LoopRunSummary) -> Void)?

    init(storeDirectory: URL = AppPaths.supportDirectory(),
         filePanels: FilePanelPresenting? = nil) {
        self.storeDirectory = storeDirectory
        self.filePanels = filePanels ?? AppKitFilePanels()
        load()
    }

    /// The (cached) run controller for a loop — create-on-miss. Safe to call from
    /// a view body: creation mutates only the @ObservationIgnored registry;
    /// `runningLoopIDs` changes only inside the controller's callbacks.
    func runController(for id: LoopPlan.ID) -> LoopRunController {
        if let existing = runControllers[id] { return existing }
        let controller = LoopRunController()
        controller.onRunningChanged = { [weak self] running in
            guard let self else { return }
            if running { self.runningLoopIDs.insert(id) }
            else { self.runningLoopIDs.remove(id) }
        }
        controller.onFinished = { [weak self] summary in
            guard let self else { return }
            if let i = self.loops.firstIndex(where: { $0.id == id }) {
                self.loops[i].lastRun = summary
                self.loops[i].lastRunAt = summary.date
                // Roll the lifetime health counters (the article's "cost per accepted
                // change"): every finished run counts; a verified PASS is an accepted
                // change. A `nil` pass (done-but-unverified) counts as a run but not an
                // acceptance, so it can't inflate the health signal.
                self.loops[i].lifetimeRuns += 1
                if summary.pass == true { self.loops[i].lifetimeAccepted += 1 }
                self.loops[i].lifetimeCostUSD += max(0, summary.costUSD)
                self.save()
                // Post-run reflection: harvest what the loop + its verifier wrote into
                // STATE.md into the global knowledge base, so lessons survive this loop
                // and feed future teams. Honest (STATE.md is real, not fabricated) and
                // deduped; only when the loop uses memory.
                if self.loops[i].memoryEnabled {
                    let repo = self.workingURL(for: self.loops[i])
                    MemoryStore.shared.harvestStateFile(at: repo)
                }
            }
            self.onRunFinished?(id, summary)
        }
        runControllers[id] = controller
        return controller
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
        // Stop and drop any in-flight run before the plan disappears.
        runControllers[id]?.stop()
        runControllers[id] = nil
        runningLoopIDs.remove(id)
        // Tear down the LaunchAgent too (idempotent no-op when none exists) —
        // otherwise a scheduled loop keeps running loop.sh against the user's
        // repo forever, with no surface left in the app to see or stop it.
        LoopScheduler.disable(id)
        // And drop the private per-loop scratch workspace, if one was created.
        try? FileManager.default.removeItem(
            at: AppPaths.supportDirectory()
                .appendingPathComponent("loop-workspaces/\(id.uuidString)", isDirectory: true))
        loops.removeAll { $0.id == id }
        liveRepoURLs[id] = nil
        if selectedLoopID == id { selectedLoopID = loops.first?.id }
        save()
    }

    // MARK: - Repo selection

    /// Present an open panel to choose the target repo folder for a plan.
    /// Mirrors AppModel.pickRepo (security-scoped bookmark + live URL cache).
    func pickRepo(for id: LoopPlan.ID) {
        // Same locale heuristic as ChatViewModel.narrationLang: the store has no
        // AppSettings handle, and the panel copy should still follow the system.
        let lang = (Locale.preferredLanguages.first?.hasPrefix("es") == true) ? "es" : "en"
        guard let url = filePanels.chooseDirectory(
                prompt: L10n.string("repo.picker.prompt", langCode: lang),
                message: L10n.string("loop.repo.picker.message", langCode: lang),
                startingAt: nil),
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
        if let data = plan.repoBookmark, let res = SecurityScopedBookmark.resolve(data) {
            liveRepoURLs[plan.id] = res.url
            // A stale bookmark was regenerated — persist the fresh data out of the render
            // pass (repoURL is called from view bodies).
            if let fresh = res.refreshedData {
                let id = plan.id
                Task { @MainActor in self.persistRefreshedBookmark(fresh, forPlan: id) }
            }
            return res.url
        }
        if let path = plan.repoPath { return URL(fileURLWithPath: path) }
        return nil
    }

    /// Store a regenerated security-scoped bookmark for a plan and persist it.
    private func persistRefreshedBookmark(_ data: Data, forPlan id: LoopPlan.ID) {
        guard let i = loops.firstIndex(where: { $0.id == id }),
              loops[i].repoBookmark != data else { return }
        loops[i].repoBookmark = data
        save()
    }

    /// Where a run actually works: the user's chosen project folder, or a private
    /// per-loop workspace so a loop that ISN'T tied to a code project (a writing or
    /// design task) still runs somewhere — the folder is optional, mirroring how chats
    /// fall back to a per-chat scratch folder.
    func workingURL(for plan: LoopPlan) -> URL {
        if let url = repoURL(for: plan) { return url }
        let dir = AppPaths.supportDirectory()
            .appendingPathComponent("loop-workspaces/\(plan.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// True when the loop targets the user's OWN folder (needs security-scoped access),
    /// vs an app-owned scratch workspace (which doesn't).
    func hasUserFolder(for plan: LoopPlan) -> Bool { repoURL(for: plan) != nil }

    // MARK: - Persistence (JSON in Application Support)

    /// Versioned wrapper with a tolerant decode, mirroring AppModel.PersistedState.
    private struct PersistedLoops: Codable {
        static let currentVersion = 1

        var schemaVersion: Int
        var loops: [LoopPlan]
        /// The last-open loop, restored across launches (device-local).
        var selectedLoopID: UUID?

        init(loops: [LoopPlan], selectedLoopID: UUID? = nil, schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.loops = loops
            self.selectedLoopID = selectedLoopID
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, loops, selectedLoopID }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            // Lossy per-element: one corrupt loop must not empty the whole library.
            if let all = try? c.decodeIfPresent([LoopPlan].self, forKey: .loops) {
                loops = all ?? []
            } else if var u = try? c.nestedUnkeyedContainer(forKey: .loops) {
                var out: [LoopPlan] = []
                while !u.isAtEnd {
                    if let v = try? u.decode(LoopPlan.self) { out.append(v) } else { _ = try? u.decode(DecoderSkip.self) }
                }
                loops = out
            } else {
                loops = []
            }
            selectedLoopID = ((try? c.decodeIfPresent(UUID.self, forKey: .selectedLoopID)) ?? nil)
        }
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("loops.json")
    }

    /// Persist the store. Loops are small, so a synchronous atomic write keeps
    /// this simple; failures surface through `onError` (a silent save failure
    /// would silently lose loops).
    func save() {
        let state = PersistedLoops(loops: loops, selectedLoopID: selectedLoopID)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            onError?("banner.loopsSaveFailed", error.localizedDescription)
        }
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
            // Park the error: load() runs before any banner surface exists, so
            // the app shell flushes this on appear.
            loadError = ("banner.loopsCorrupt", backup.lastPathComponent)
            return
        }
        loops = decoded.loops
        if let sel = decoded.selectedLoopID, loops.contains(where: { $0.id == sel }) {
            selectedLoopID = sel
        } else {
            selectedLoopID = loops.first?.id
        }
    }
}
