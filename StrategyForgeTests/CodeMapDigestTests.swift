//
//  CodeMapDigestTests.swift
//  StrategyForgeTests
//
//  Unit tests for the map digest injected into agent sessions and its (honest) saving
//  estimate. The digest is a pure string builder; the estimate is deterministic given a
//  repo path (file sizes on disk), so we test the math with a path that has no files
//  (cold-read = 0 → saving floors at 0) plus the digest content shape.
//

import Testing
import Foundation
@testable import Coral

struct CodeMapDigestTests {

    private func sample() -> CodeGraph {
        let nodes = [
            CodeGraph.Node(id: "auth_hub", label: "auth.swift", kind: "code", community: 0,
                           communityName: "Authentication", file: "auth.swift", line: 1, degree: 3),
            CodeGraph.Node(id: "login", label: "login", kind: "function", community: 0,
                           communityName: "Authentication", file: "auth.swift", line: 20, degree: 1),
            CodeGraph.Node(id: "db_hub", label: "db.swift", kind: "code", community: 1,
                           communityName: "Storage", file: "db.swift", line: 1, degree: 2),
        ]
        let edges = [
            CodeGraph.Edge(source: "auth_hub", target: "login", label: "contains"),
            CodeGraph.Edge(source: "auth_hub", target: "db_hub", label: "calls"),   // cross-cluster
        ]
        return CodeGraph(nodes: nodes, edges: edges, communityCount: 2)
    }

    @Test func digestNamesClustersHubsAndSeams() {
        let d = CodeMapDigest.render(sample(), repoName: "MyRepo")
        #expect(d.contains("MyRepo"))
        #expect(d.contains("Authentication"))          // named cluster from community_name
        #expect(d.contains("Storage"))
        #expect(d.contains("auth.swift:1"))            // hub with file:line
        #expect(d.contains("Cross-cluster"))           // the seam section
        #expect(d.contains("`auth.swift` → `db.swift`"))
    }

    @Test func estimateFloorsAtZeroWhenNoFilesOnDisk() {
        let d = CodeMapDigest.render(sample(), repoName: "MyRepo")
        // A path with no matching files → cold-read baseline is 0, so the saving can't go
        // negative and the digest tokens are still counted.
        let est = CodeMapDigest.estimate(digest: d, graph: sample(), repoPath: "/nonexistent/repo/xyz")
        #expect(est.digestTokens == max(1, d.count / 4))
        #expect(est.coldReadTokens == 0)
        #expect(est.savedTokens == 0)
        #expect(est.savedUSD == 0)
    }

    @Test func estimateCountsRealFileBytesAsColdRead() throws {
        // Write a real file the graph references, so cold-read reflects its size.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-digest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let big = String(repeating: "x", count: 40_000)   // ~10k tokens
        try big.write(to: tmp.appendingPathComponent("auth.swift"), atomically: true, encoding: .utf8)

        let d = CodeMapDigest.render(sample(), repoName: "MyRepo")
        let est = CodeMapDigest.estimate(digest: d, graph: sample(), repoPath: tmp.path)
        #expect(est.coldReadTokens >= 9_000)             // ~40_000 / 4
        #expect(est.savedTokens == max(0, est.coldReadTokens - est.digestTokens))
        #expect(est.savedTokens > 0)
    }
}
