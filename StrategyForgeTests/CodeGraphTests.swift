//
//  CodeGraphTests.swift
//  StrategyForgeTests
//
//  Unit tests for CodeGraph.parse — the tolerant adapter over graphify's `graph.json`.
//  The parser is the one piece of real logic in the Map feature (the rest is rendering
//  and process plumbing), and it deliberately accepts several shapes, so these pin the
//  variants it must survive: NetworkX node-link, index-referenced links, key aliases,
//  integer ids, community normalisation, degree, and graceful failure on junk.
//

import Testing
import Foundation
@testable import Coral

struct CodeGraphTests {

    private func parse(_ json: String) -> CodeGraph? {
        CodeGraph.parse(Data(json.utf8))
    }

    // MARK: - Shape acceptance

    @Test func parsesNetworkXNodeLinkWithStringIDs() {
        let g = parse("""
        { "nodes": [{"id":"a","label":"Alpha","community":0,"file":"a.swift","line":10},
                    {"id":"b","label":"Beta","community":1}],
          "links": [{"source":"a","target":"b","type":"calls"}] }
        """)
        #expect(g != nil)
        #expect(g?.nodes.count == 2)
        #expect(g?.edges.count == 1)
        #expect(g?.edges.first?.label == "calls")
        let a = g?.nodes.first { $0.id == "a" }
        #expect(a?.label == "Alpha")
        #expect(a?.file == "a.swift")
        #expect(a?.line == 10)
    }

    @Test func resolvesIndexReferencedLinks() {
        // NetworkX can emit links referencing node ARRAY INDICES rather than ids.
        let g = parse("""
        { "nodes": [{"id":"x"},{"id":"y"},{"id":"z"}],
          "links": [{"source":0,"target":2}] }
        """)
        #expect(g?.edges.count == 1)
        #expect(g?.edges.first?.source == "x")
        #expect(g?.edges.first?.target == "z")
    }

    @Test func acceptsEdgesKeyAndFromToAliases() {
        let g = parse("""
        { "nodes": [{"id":"a"},{"id":"b"}],
          "edges": [{"from":"a","to":"b"}] }
        """)
        #expect(g?.edges.count == 1)
        #expect(g?.edges.first?.source == "a")
    }

    @Test func integerIDsAndNameAliasWork() {
        let g = parse("""
        { "nodes": [{"id":1,"name":"one"},{"id":2,"name":"two"}],
          "links": [{"source":1,"target":2}] }
        """)
        #expect(g?.nodes.count == 2)
        #expect(g?.nodes.first { $0.id == "1" }?.label == "one")
        #expect(g?.edges.first?.target == "2")
    }

    // MARK: - Normalisation

    @Test func communitiesNormaliseToDenseZeroBasedAndCountsClusters() {
        // Arbitrary community tokens (here: 5, 5, 42) collapse to 0..<2.
        let g = parse("""
        { "nodes": [{"id":"a","group":5},{"id":"b","group":5},{"id":"c","group":42}],
          "links": [] }
        """)
        #expect(g?.communityCount == 2)
        let comms = Set((g?.nodes ?? []).map { $0.community })
        #expect(comms == Set([0, 1]))
    }

    @Test func degreeCountsIncidentEdges() {
        let g = parse("""
        { "nodes": [{"id":"hub"},{"id":"a"},{"id":"b"}],
          "links": [{"source":"hub","target":"a"},{"source":"hub","target":"b"}] }
        """)
        #expect(g?.nodes.first { $0.id == "hub" }?.degree == 2)
        #expect(g?.nodes.first { $0.id == "a" }?.degree == 1)
    }

    @Test func dropsSelfLoopsAndDanglingEdges() {
        let g = parse("""
        { "nodes": [{"id":"a"},{"id":"b"}],
          "links": [{"source":"a","target":"a"},{"source":"a","target":"ghost"},{"source":"a","target":"b"}] }
        """)
        #expect(g?.edges.count == 1)   // only a→b survives
    }

    @Test func unwrapsGraphWrapper() {
        let g = parse("""
        { "graph": { "nodes": [{"id":"a"},{"id":"b"}], "links": [{"source":"a","target":"b"}] } }
        """)
        #expect(g?.nodes.count == 2)
        #expect(g?.edges.count == 1)
    }

    // MARK: - Failure

    @Test func returnsNilOnJunkOrEmpty() {
        #expect(parse("not json") == nil)
        #expect(parse("{}") == nil)
        #expect(parse("{ \"nodes\": [] }") == nil)   // empty node list → nil
    }
}
