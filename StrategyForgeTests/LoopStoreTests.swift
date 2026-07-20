//
//  LoopStoreTests.swift
//  StrategyForgeTests
//
//  LoopStore's repo-binding path through the FilePanelPresenting seam (#12),
//  exercised over a real temp directory — no modal, no Application Support.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Coral

/// A file-panel presenter that returns a preset URL instead of showing a modal.
@MainActor
private struct FakeLoopPanels: FilePanelPresenting {
    var directory: URL?
    func chooseDirectory(prompt: String?, message: String?, startingAt: URL?) -> URL? { directory }
    func chooseFile(contentTypes: [UTType], prompt: String?) -> URL? { nil }
    func save(suggestedName: String, contentTypes: [UTType]) -> URL? { nil }
}

@MainActor
struct LoopStoreTests {

    /// A fresh temp directory that's removed when `body` returns.
    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func pickRepoBindsTheFolderFromTheInjectedPanel() throws {
        try withTempDir { dir in
            let picked = dir.appendingPathComponent("MyRepo", isDirectory: true)
            try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
            let store = LoopStore(storeDirectory: dir, filePanels: FakeLoopPanels(directory: picked))

            let id = store.addLoop()
            store.pickRepo(for: id)

            let plan = store.loops.first { $0.id == id }
            #expect(plan?.repoPath == picked.path)
            #expect(store.repoURL(for: plan!) == picked)

            // The binding round-trips: a second store over the SAME dir sees it.
            let reloaded = LoopStore(storeDirectory: dir)
            #expect(reloaded.loops.first { $0.id == id }?.repoPath == picked.path)
        }
    }

    @Test func cancelledPanelLeavesThePlanUnbound() throws {
        try withTempDir { dir in
            let store = LoopStore(storeDirectory: dir, filePanels: FakeLoopPanels(directory: nil))
            let id = store.addLoop()
            store.pickRepo(for: id)
            #expect(store.loops.first { $0.id == id }?.repoPath == nil)
        }
    }
}
