//
//  SyncTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for the portable/device-local split, last-writer-wins merge,
//  and tolerant persistence versioning. None of these touch disk or CloudKit.
//

import Testing
import Foundation
@testable import Coral

struct PortableConfigurationTests {

    @Test func portableProjectionDropsRepoBinding() {
        var config = Configuration(name: "Team", strategy: StrategyLibrary.solo(),
                                   repoPath: "/Users/me/secret-project",
                                   repoBookmark: Data([1, 2, 3]),
                                   updatedAt: Date(timeIntervalSince1970: 100))
        config.name = "Team"
        let portable = config.portable

        // Portable carries content + timestamp...
        #expect(portable.id == config.id)
        #expect(portable.name == "Team")
        #expect(portable.updatedAt == config.updatedAt)

        // ...and by construction cannot carry the bookmark: the encoded portable
        // JSON must not contain repoPath/repoBookmark keys.
        let json = String(data: try! JSONEncoder().encode(portable), encoding: .utf8)!
        #expect(!json.contains("repoBookmark"))
        #expect(!json.contains("repoPath"))
        #expect(!json.contains("secret-project"))
    }

    @Test func applyPortablePreservesLocalRepoBinding() {
        var local = Configuration(name: "Old", strategy: StrategyLibrary.solo(),
                                  repoPath: "/Users/me/app", repoBookmark: Data([9]),
                                  updatedAt: Date(timeIntervalSince1970: 1))
        let incoming = PortableConfiguration(id: local.id, name: "New name",
                                             strategy: StrategyLibrary.researchFanout(),
                                             updatedAt: Date(timeIntervalSince1970: 2))
        local.applyPortable(incoming)

        #expect(local.name == "New name")           // portable content updated
        #expect(local.repoPath == "/Users/me/app")  // device-local binding kept
        #expect(local.repoBookmark == Data([9]))
    }
}

struct ConfigMergerTests {

    private func cfg(_ name: String, _ t: TimeInterval, id: UUID) -> Configuration {
        Configuration(id: id, name: name, strategy: StrategyLibrary.solo(),
                      updatedAt: Date(timeIntervalSince1970: t))
    }

    @Test func remoteOnlyConfigsAreAppended() {
        let remote = [PortableConfiguration(id: UUID(), name: "From other Mac",
                                            strategy: StrategyLibrary.solo(),
                                            updatedAt: Date(timeIntervalSince1970: 5))]
        let merged = ConfigMerger.merge(local: [], remote: remote).configurations
        #expect(merged.count == 1)
        #expect(merged.first?.name == "From other Mac")
        #expect(merged.first?.repoPath == nil) // no repo binding travels
    }

    @Test func newerRemoteWinsOlderLocalKept() {
        let id1 = UUID(), id2 = UUID()
        let local = [cfg("local-old", 1, id: id1), cfg("local-newer", 10, id: id2)]
        let remote = [
            PortableConfiguration(id: id1, name: "remote-newer", strategy: StrategyLibrary.solo(),
                                  updatedAt: Date(timeIntervalSince1970: 5)),   // wins over id1
            PortableConfiguration(id: id2, name: "remote-old", strategy: StrategyLibrary.solo(),
                                  updatedAt: Date(timeIntervalSince1970: 2)),   // loses to id2
        ]
        let result = ConfigMerger.merge(local: local, remote: remote)
        #expect(result.configurations.count == 2)
        #expect(result.conflictCount == 0)   // no baseline → plain last-writer-wins
        #expect(result.configurations.first(where: { $0.id == id1 })?.name == "remote-newer")
        #expect(result.configurations.first(where: { $0.id == id2 })?.name == "local-newer")
    }

    @Test func divergentEditIsKeptAsConflictCopy() {
        // Both Macs edited the same chat since the last sync (baseline t=1): local bumped
        // to t=5 with a new name, remote bumped to t=10 with a different name. Remote wins
        // by LWW, but the local edit must survive as a "(conflict)" copy, not vanish.
        let id = UUID()
        let local = [cfg("local-edit", 5, id: id)]
        let remote = [PortableConfiguration(id: id, name: "remote-edit", strategy: StrategyLibrary.solo(),
                                            updatedAt: Date(timeIntervalSince1970: 10))]
        let baseline = [id: Date(timeIntervalSince1970: 1)]
        let result = ConfigMerger.merge(local: local, remote: remote, baseline: baseline,
                                        conflictSuffix: " (conflict)")
        #expect(result.conflictCount == 1)
        #expect(result.configurations.count == 2)
        // Canonical id now holds the remote (winning) version...
        #expect(result.configurations.first(where: { $0.id == id })?.name == "remote-edit")
        // ...and the local edit is preserved under a fresh id with the conflict suffix.
        let clone = result.configurations.first { $0.id != id }
        #expect(clone?.name == "local-edit (conflict)")
    }

    @Test func staleLocalIsNotAConflict() {
        // Local was NEVER edited since baseline (updatedAt == baseline): a newer remote is
        // just a normal update, not a conflict — no copy should be spawned.
        let id = UUID()
        let local = [cfg("synced", 1, id: id)]
        let remote = [PortableConfiguration(id: id, name: "remote-newer", strategy: StrategyLibrary.solo(),
                                            updatedAt: Date(timeIntervalSince1970: 10))]
        let baseline = [id: Date(timeIntervalSince1970: 1)]
        let result = ConfigMerger.merge(local: local, remote: remote, baseline: baseline)
        #expect(result.conflictCount == 0)
        #expect(result.configurations.count == 1)
        #expect(result.configurations.first?.name == "remote-newer")
    }

    @Test func identicalContentIsNotAConflict() {
        // Both sides diverged in timestamp but the portable content is identical — there's
        // nothing to reconcile, so no "(conflict)" copy. Share ONE strategy value so the
        // two sides compare equal (a fresh StrategyLibrary.solo() carries distinct role ids).
        let id = UUID()
        let strategy = StrategyLibrary.solo()
        let local = [Configuration(id: id, name: "same", strategy: strategy,
                                   updatedAt: Date(timeIntervalSince1970: 5))]
        let remote = [PortableConfiguration(id: id, name: "same", strategy: strategy,
                                            updatedAt: Date(timeIntervalSince1970: 10))]
        let baseline = [id: Date(timeIntervalSince1970: 1)]
        let result = ConfigMerger.merge(local: local, remote: remote, baseline: baseline)
        #expect(result.conflictCount == 0)
        #expect(result.configurations.count == 1)
    }
}

struct PersistenceVersioningTests {

    @Test func decodesPreVersionedFileAndMigrates() throws {
        // A file written before schemaVersion/updatedAt existed.
        let legacy = """
        {
          "configurations": [
            { "id": "\(UUID().uuidString)", "name": "Legacy",
              "strategy": \(strategyJSON()) }
          ],
          "settings": {}
        }
        """
        let data = legacy.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppModel.PersistedState.self, from: data)
        #expect(decoded.schemaVersion == 0)          // pre-versioned
        #expect(decoded.configurations.count == 1)
        #expect(decoded.configurations.first?.updatedAt == .distantPast) // tolerant default

        let migrated = decoded.migrated()
        #expect(migrated.schemaVersion == AppModel.PersistedState.currentVersion)
    }

    private func strategyJSON() -> String {
        let data = try! JSONEncoder().encode(StrategyLibrary.solo())
        return String(data: data, encoding: .utf8)!
    }
}
