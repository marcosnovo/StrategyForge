//
//  MapStoreTests.swift
//  StrategyForgeTests
//
//  MapStore persists code maps (cached graph.json + index) so they survive leaving the
//  section and reopen instantly/free. These verify the record → persist → reload-in-a-new
//  instance roundtrip, and that keys are stable (so the same repo maps to the same cache).
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct MapStoreTests {

    @Test func recordsCachesAndReloadsAcrossInstances() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-mapstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let storeDir = base.appendingPathComponent("store", isDirectory: true)
        let repo = base.appendingPathComponent("repo", isDirectory: true)
        let out = repo.appendingPathComponent("graphify-out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let json = #"{ "nodes": [{"id":"a","community":0},{"id":"b","community":1}], "links": [{"source":"a","target":"b"}] }"#
        try json.write(to: out.appendingPathComponent("graph.json"), atomically: true, encoding: .utf8)
        let graph = try #require(CodeGraph.parse(Data(json.utf8)))

        let store1 = MapStore(storeDirectory: storeDir)
        store1.record(repoURL: repo, graph: graph, kind: .github, subtitle: "acme/widget")
        #expect(store1.maps.count == 1)
        #expect(store1.maps.first?.id == "gh-acme-widget")
        #expect(store1.maps.first?.nodeCount == 2)
        #expect(store1.maps.first?.communityCount == 2)

        // A fresh instance must read the persisted index and the cached graph.
        let store2 = MapStore(storeDirectory: storeDir)
        #expect(store2.maps.count == 1)
        let reloaded = store2.loadGraph(try #require(store2.maps.first))
        #expect(reloaded?.nodes.count == 2)
        #expect(reloaded?.edges.count == 1)
    }

    @Test func keysAreStableAndDeterministic() {
        #expect(MapStore.key(kind: .github, subtitle: "acme/widget") == "gh-acme-widget")
        #expect(MapStore.key(kind: .local, subtitle: "/a/b").hasPrefix("local-"))
        #expect(MapStore.key(kind: .local, subtitle: "/a/b") == MapStore.key(kind: .local, subtitle: "/a/b"))
        #expect(MapStore.key(kind: .local, subtitle: "/a/b") != MapStore.key(kind: .local, subtitle: "/a/c"))
    }
}
