//
//  AppModelPersistenceTests.swift
//  StrategyForgeTests
//
//  Exercises the store round-trip through a real (temp) directory, enabled by the
//  init(storeDirectory:) testability seam (#12). No Application Support, no network.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Coral

/// A file-panel presenter that returns preset URLs instead of showing a modal.
@MainActor
private struct FakeFilePanels: FilePanelPresenting {
    var directory: URL?
    var file: URL?
    var saveURL: URL?
    func chooseDirectory(prompt: String?, message: String?, startingAt: URL?) -> URL? { directory }
    func chooseFile(contentTypes: [UTType], prompt: String?) -> URL? { file }
    func save(suggestedName: String, contentTypes: [UTType]) -> URL? { saveURL }
}

@MainActor
struct AppModelPersistenceTests {

    /// A fresh temp directory that's removed when `body` returns.
    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func configurationsRoundTripThroughDisk() throws {
        try withTempDir { dir in
            // A model pointed at an empty temp dir starts blank (autoLoad finds no file).
            let model = AppModel(storeDirectory: dir)
            let before = model.configurations.count

            var config = Configuration(name: "Persisted", strategy: StrategyLibrary.solo())
            config.updatedAt = Date(timeIntervalSince1970: 1000)
            model.configurations.append(config)
            model.save(stamp: false, sync: true)   // synchronous write to the temp dir

            // A second model over the SAME dir must see the saved configuration.
            let reloaded = AppModel(storeDirectory: dir)
            #expect(reloaded.configurations.count == before + 1)
            #expect(reloaded.configurations.contains { $0.name == "Persisted" })
        }
    }

    @Test func savedTeamsRoundTripThroughTheLibrary() throws {
        try withTempDir { dir in
            let model = AppModel(storeDirectory: dir)
            let team = SavedTeam(name: "My preset", strategy: StrategyLibrary.researchFanout())
            model.savedTeams.append(team)                 // writes through TeamLibrary
            #expect(model.teamLibrary.teams.contains { $0.id == team.id })
            model.save(stamp: false, sync: true)

            let reloaded = AppModel(storeDirectory: dir)
            #expect(reloaded.savedTeams.contains { $0.name == "My preset" })
        }
    }

    @Test func corruptStoreIsBackedUpNotFatal() throws {
        try withTempDir { dir in
            // A garbage data.json must not crash load; the model just starts empty and
            // (per the load() path) leaves a backup rather than deleting the file.
            let bad = dir.appendingPathComponent("data.json")
            try Data("{ this is not json".utf8).write(to: bad)
            let model = AppModel(storeDirectory: dir)
            #expect(model.configurations.isEmpty)
        }
    }

    @Test func pickRepoBindsTheFolderFromTheInjectedPanel() throws {
        try withTempDir { dir in
            // A fake panel returns a preset folder — no modal — so repo-binding is testable.
            let picked = dir.appendingPathComponent("MyRepo", isDirectory: true)
            try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
            let model = AppModel(storeDirectory: dir, filePanels: FakeFilePanels(directory: picked))

            var config = Configuration(name: "Bind me", strategy: StrategyLibrary.solo())
            model.configurations.append(config)
            config = model.configurations[0]

            let bound = model.pickRepo(for: config.id)
            #expect(bound)
            #expect(model.configurations[0].repoPath == picked.path)
        }
    }

    @Test func undoRestoresADeletedChatWithinTheWindow() throws {
        try withTempDir { dir in
            let model = AppModel(storeDirectory: dir)
            var config = Configuration(name: "Keep me", strategy: StrategyLibrary.solo())
            config.transcript = [ChatMessage(role: .user, text: "hello")]
            model.configurations.append(config)
            let id = config.id

            model.deleteConfiguration(id)
            // Gone from the list, tombstoned, and an Undo is offered.
            #expect(!model.configurations.contains { $0.id == id })
            #expect(model.deletedConfigIDs.contains(id))
            #expect(model.bannerCenter.pendingUndo != nil)

            model.undoDelete(id)
            // Restored with its transcript, un-tombstoned, and reselected.
            let restored = model.configurations.first { $0.id == id }
            #expect(restored != nil)
            #expect(restored?.transcript.first?.text == "hello")
            #expect(!model.deletedConfigIDs.contains(id))
            #expect(model.selectedConfigID == id)
        }
    }

    @Test func flushSavesDoesNotFinalizeAPendingDelete() throws {
        try withTempDir { dir in
            // flushSaves fires on ANY leave-foreground (hide, deactivate) — it must not
            // hard-delete a chat that's still inside its undo window.
            let model = AppModel(storeDirectory: dir)
            var config = Configuration(name: "Undoable", strategy: StrategyLibrary.solo())
            config.transcript = [ChatMessage(role: .user, text: "hello")]
            model.configurations.append(config)
            let id = config.id
            model.updateTranscript(id, config.transcript)
            model.flushSaves()   // transcript writes are coalesced — force the sidecar to disk
            let sidecar = dir.appendingPathComponent("transcripts/\(id.uuidString).json")
            #expect(FileManager.default.fileExists(atPath: sidecar.path))

            model.deleteConfiguration(id)
            model.flushSaves()

            // The sidecar survived the flush and the Undo still works.
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            model.undoDelete(id)
            #expect(model.configurations.contains { $0.id == id })
        }
    }

    @Test func finalizeOnTerminateHardDeletesPendingChats() throws {
        try withTempDir { dir in
            // Real termination is the point of no return: pending deletes finalize
            // (sidecars removed) and the Undo becomes a no-op.
            let model = AppModel(storeDirectory: dir)
            var config = Configuration(name: "Doomed", strategy: StrategyLibrary.solo())
            config.transcript = [ChatMessage(role: .user, text: "bye")]
            model.configurations.append(config)
            let id = config.id
            model.updateTranscript(id, config.transcript)
            model.flushSaves()   // the sidecar must exist for its removal to mean anything
            let sidecar = dir.appendingPathComponent("transcripts/\(id.uuidString).json")
            #expect(FileManager.default.fileExists(atPath: sidecar.path))

            model.deleteConfiguration(id)
            model.finalizeOnTerminate()

            #expect(!FileManager.default.fileExists(atPath: sidecar.path))
            model.undoDelete(id)   // window is over — nothing to restore
            #expect(!model.configurations.contains { $0.id == id })
        }
    }

    @Test func launchSweepClearsTombstonedSidecarsAndDanglingLinks() throws {
        try withTempDir { dir in
            // Simulate a hard crash inside the undo window: the chat is tombstoned and
            // gone from data.json, but the deferred finalize never ran, so its sidecar
            // and a continuedFrom link pointing at it are left behind.
            let model = AppModel(storeDirectory: dir)
            let ancestor = Configuration(name: "Ancestor", strategy: StrategyLibrary.solo())
            var child = Configuration(name: "Child", strategy: StrategyLibrary.solo())
            child.continuedFrom = ancestor.id
            model.configurations.append(ancestor)
            model.configurations.append(child)
            model.updateTranscript(ancestor.id, [ChatMessage(role: .user, text: "bye")])
            model.flushSaves()   // transcript writes are coalesced — force the sidecar to disk
            model.configurations.removeAll { $0.id == ancestor.id }
            model.deletedConfigIDs.insert(ancestor.id)
            model.save(stamp: false, sync: true)

            let sidecar = dir.appendingPathComponent("transcripts/\(ancestor.id.uuidString).json")
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            // A NON-tombstoned orphan (e.g. a chat dropped by the lossy decode) must
            // survive the sweep — only tombstoned ids may be GC'd.
            let strayID = UUID()
            let stray = dir.appendingPathComponent("transcripts/\(strayID.uuidString).json")
            try Data("[]".utf8).write(to: stray)

            let reloaded = AppModel(storeDirectory: dir)
            #expect(!FileManager.default.fileExists(atPath: sidecar.path))
            #expect(FileManager.default.fileExists(atPath: stray.path))
            #expect(reloaded.configurations.first { $0.id == child.id }?.continuedFrom == nil)
        }
    }

    @Test func staleSaveGenerationNeverOverwritesANewerWrite() throws {
        try withTempDir { dir in
            // A detached save that already passed its cancellation check must not land
            // after — and clobber — a newer write (including the final one on quit).
            let url = dir.appendingPathComponent("data.json")
            let serializer = SaveSerializer()
            try serializer.write(Data("new".utf8), to: url, generation: 2)
            try serializer.write(Data("stale".utf8), to: url, generation: 1)   // dropped
            #expect(String(data: try Data(contentsOf: url), encoding: .utf8) == "new")
            try serializer.write(Data("newest".utf8), to: url, generation: 3)
            #expect(String(data: try Data(contentsOf: url), encoding: .utf8) == "newest")
        }
    }

    @Test func undoBannerLivesAsLongAsTheUndoWindow() {
        // The delete banner's Undo button must not vanish (4s success default) while
        // the chat is still restorable (10s window) — both read the same constant.
        #expect(BannerCenter.dismissDelay(for: .success("x"), override: AppModel.undoWindow)
                == AppModel.undoWindow)
        #expect(AppModel.undoWindow == .seconds(10))
        #expect(BannerCenter.dismissDelay(for: .success("x"), override: nil) == .seconds(4))
        #expect(BannerCenter.dismissDelay(for: .failure("x"), override: nil) == .seconds(12))
    }

    @Test func switchingChatsClearsTheDiffReviewPanelState() throws {
        try withTempDir { dir in
            // diffReview is a single global slot: chat A's findings must never render
            // under chat B's Code Mode after a selection change.
            let model = AppModel(storeDirectory: dir)
            let a = Configuration(name: "A", strategy: StrategyLibrary.solo())
            let b = Configuration(name: "B", strategy: StrategyLibrary.solo())
            model.configurations.append(a)
            model.configurations.append(b)
            model.selectedConfigID = a.id
            model.diffReview = DiffReview(findings: [])
            model.selectedConfigID = b.id
            #expect(model.diffReview == nil)
            // Re-setting the SAME selection must not clear a fresh result.
            model.diffReview = DiffReview(findings: [])
            model.selectedConfigID = b.id
            #expect(model.diffReview != nil)
        }
    }

    @Test func flushSavesLandsPendingTranscriptWritesSynchronously() throws {
        try withTempDir { dir in
            // updateTranscript's encode + write are coalesced off the main actor; the
            // background/quit flush must still land the latest snapshot on THIS thread.
            let model = AppModel(storeDirectory: dir)
            let config = Configuration(name: "Stream", strategy: StrategyLibrary.solo())
            model.configurations.append(config)
            model.updateTranscript(config.id, [ChatMessage(role: .user, text: "hi")])
            model.updateTranscript(config.id, [ChatMessage(role: .user, text: "hi"),
                                               ChatMessage(role: .assistant, text: "there")])
            model.flushSaves()

            let sidecar = dir.appendingPathComponent("transcripts/\(config.id.uuidString).json")
            let data = try Data(contentsOf: sidecar)
            let messages = try #require(AppModel.decodeMessagesTolerantly(data))
            #expect(messages.map(\.text) == ["hi", "there"])   // the NEWEST snapshot won
        }
    }

    @Test func serializerBarrierDropsStragglingWrites() throws {
        try withTempDir { dir in
            // finalizeDelete barriers the chat's serializer before deleting the sidecar,
            // so an in-flight detached write can't re-create the deleted file.
            let url = dir.appendingPathComponent("t.json")
            let serializer = SaveSerializer()
            try serializer.write(Data("live".utf8), to: url, generation: 1)
            serializer.barrier(upTo: 2)
            try FileManager.default.removeItem(at: url)
            try serializer.write(Data("straggler".utf8), to: url, generation: 2)   // dropped
            #expect(!FileManager.default.fileExists(atPath: url.path))
            try serializer.write(Data("newer".utf8), to: url, generation: 3)       // future writes still land
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func transcriptsHydrateLazilyAfterLaunch() throws {
        try withTempDir { dir in
            // Launch must not decode every chat's history up front: only the restored
            // selection hydrates synchronously; another chat hydrates on demand the
            // moment it's selected (before its ChatViewModel is built).
            let model = AppModel(storeDirectory: dir)
            let a = Configuration(name: "A", strategy: StrategyLibrary.solo())
            let b = Configuration(name: "B", strategy: StrategyLibrary.solo())
            model.configurations.append(a)
            model.configurations.append(b)
            model.selectedConfigID = a.id
            model.updateTranscript(a.id, [ChatMessage(role: .user, text: "alpha")])
            model.updateTranscript(b.id, [ChatMessage(role: .user, text: "beta")])
            model.rememberSelection()
            model.flushSaves()

            let reloaded = AppModel(storeDirectory: dir)
            // The restored selection is ready for its first-frame ChatViewModel…
            #expect(reloaded.selectedConfigID == a.id)
            #expect(reloaded.configurations.first { $0.id == a.id }?.transcript.first?.text == "alpha")
            // …the other chat is not hydrated yet (the background task can't have
            // applied inside this synchronous main-actor window)…
            #expect(reloaded.configurations.first { $0.id == b.id }?.transcript.isEmpty == true)
            // …and selecting it hydrates on demand, synchronously.
            reloaded.selectedConfigID = b.id
            #expect(reloaded.configurations.first { $0.id == b.id }?.transcript.first?.text == "beta")
        }
    }

    @Test func deletingAnUnhydratedChatStillRestoresItsTranscriptOnUndo() throws {
        try withTempDir { dir in
            // The undo copy is snapshotted in memory at delete time — a chat the
            // background hydration hasn't reached yet must hydrate first, or Undo
            // would restore an empty transcript over a sidecar about to be finalized.
            let model = AppModel(storeDirectory: dir)
            let a = Configuration(name: "A", strategy: StrategyLibrary.solo())
            let b = Configuration(name: "B", strategy: StrategyLibrary.solo())
            model.configurations.append(a)
            model.configurations.append(b)
            model.selectedConfigID = a.id
            model.updateTranscript(b.id, [ChatMessage(role: .user, text: "keep")])
            model.rememberSelection()
            model.flushSaves()

            let reloaded = AppModel(storeDirectory: dir)
            reloaded.deleteConfiguration(b.id)   // b is un-hydrated at this point
            reloaded.undoDelete(b.id)
            #expect(reloaded.configurations.first { $0.id == b.id }?.transcript.first?.text == "keep")
        }
    }
}
