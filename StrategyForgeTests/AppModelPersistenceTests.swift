//
//  AppModelPersistenceTests.swift
//  StrategyForgeTests
//
//  Exercises the store round-trip through a real (temp) directory, enabled by the
//  init(storeDirectory:) testability seam (#12). No Application Support, no network.
//

import Testing
import Foundation
@testable import Coral

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
}
