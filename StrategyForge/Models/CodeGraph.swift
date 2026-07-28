//
//  CodeGraph.swift
//  StrategyForge
//
//  A parsed code knowledge graph — the `graph.json` that the `graphify` CLI writes
//  into `graphify-out/`. Graphify builds a NetworkX graph (deterministic tree-sitter
//  AST for code, clustered with Leiden), so the JSON is *usually* NetworkX's
//  node-link shape: { "nodes": [{id, …}], "links": [{source, target, …}] }. But
//  different graphify modes/versions vary the key names, so the parser here is
//  DELIBERATELY tolerant (raw JSONSerialization, many key aliases) rather than a
//  brittle Codable — the whole point of the adapter promised in the design. When it
//  can't make sense of the JSON it returns nil and the caller falls back to opening
//  graphify's own interactive `graph.html`.
//

import Foundation

/// A code knowledge graph: nodes (files/symbols/concepts), edges (calls, imports,
/// references), and Leiden communities normalised to 0..<communityCount.
struct CodeGraph: Equatable {
    struct Node: Identifiable, Equatable {
        let id: String
        var label: String
        /// Entity kind if the graph provided one ("function", "file", "class", …).
        var kind: String?
        /// Normalised community index (0..<communityCount) for colouring clusters.
        var community: Int
        /// Human-readable cluster name graphify assigns (`community_name`), when present.
        var communityName: String?
        /// Source location, when the graph carries it — powers the "jump to file:line" cue.
        var file: String?
        var line: Int?
        /// How many edges touch this node — drives node size and label priority.
        var degree: Int = 0
    }

    struct Edge: Equatable {
        var source: String
        var target: String
        var label: String?
    }

    var nodes: [Node]
    var edges: [Edge]
    var communityCount: Int

    var isEmpty: Bool { nodes.isEmpty }

    // MARK: - Tolerant parse

    /// Parse graphify's `graph.json`. Accepts the NetworkX node-link shape and common
    /// variants (`links` or `edges`; `source`/`target` or `from`/`to`; `community` /
    /// `group` / `cluster` / `module`; ids as strings OR integers OR array indices).
    static func parse(_ data: Data) -> CodeGraph? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        // A few tools wrap the graph as { "graph": {…} } — unwrap one level if needed.
        let obj: [String: Any]
        if let top = root as? [String: Any] {
            if let inner = top["graph"] as? [String: Any], inner["nodes"] != nil { obj = inner }
            else { obj = top }
        } else { return nil }

        guard let rawNodes = obj["nodes"] as? [[String: Any]] else { return nil }
        let rawEdges = (obj["links"] as? [[String: Any]])
            ?? (obj["edges"] as? [[String: Any]]) ?? []

        // Node id can be a string, a number, or (for index-referenced links) the node's
        // position in the array. Build id strings + an index→id map so links resolve
        // whether they reference ids or indices.
        func idString(_ any: Any?) -> String? {
            switch any {
            case let s as String: return s
            case let i as Int: return String(i)
            case let d as Double: return String(Int(d))
            default: return nil
            }
        }

        var indexToID: [String] = []
        var rawCommunities: [String: String] = [:]   // node id → raw community token (any type)
        var nodes: [Node] = []
        nodes.reserveCapacity(rawNodes.count)

        for (i, n) in rawNodes.enumerated() {
            let id = idString(n["id"]) ?? String(i)
            indexToID.append(id)
            let label = (n["label"] as? String)
                ?? (n["name"] as? String)
                ?? (n["title"] as? String)
                ?? id
            // graphify tags code entities with `file_type` ("code") + `_origin` ("ast");
            // keep the generic aliases first for other producers.
            let kind = (n["type"] as? String) ?? (n["kind"] as? String)
                ?? (n["category"] as? String) ?? (n["file_type"] as? String)
            let file = (n["file"] as? String) ?? (n["path"] as? String) ?? (n["source_file"] as? String)
            // Line number: a plain Int under several keys, OR graphify's `source_location`
            // string like "L12" / "L12-L18" → take the first run of digits.
            var line = (n["line"] as? Int) ?? (n["lineno"] as? Int) ?? (n["start_line"] as? Int)
            if line == nil, let loc = (n["source_location"] as? String) ?? (n["location"] as? String) {
                let digits = loc.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
                line = Int(digits)
            }
            // Community may be int or string under several keys; keep the raw token and
            // normalise to a dense 0-based index after we've seen them all.
            let commAny = n["community"] ?? n["group"] ?? n["cluster"] ?? n["module"] ?? n["partition"]
            if let token = idString(commAny) ?? (commAny as? String) {
                rawCommunities[id] = token
            }
            let communityName = n["community_name"] as? String
            nodes.append(Node(id: id, label: label, kind: kind, community: 0,
                              communityName: communityName, file: file, line: line))
        }

        // Normalise community tokens → 0..<N (stable order of first appearance).
        var communityIndex: [String: Int] = [:]
        for node in nodes {
            if let token = rawCommunities[node.id], communityIndex[token] == nil {
                communityIndex[token] = communityIndex.count
            }
        }
        let communityCount = max(communityIndex.count, 1)

        // Resolve edges (ids or indices), skipping self-loops and dangling refs.
        let validIDs = Set(indexToID)
        func resolve(_ any: Any?) -> String? {
            if let s = idString(any) {
                if validIDs.contains(s) { return s }
                // A numeric ref that isn't an id is an array index into the node list.
                if let idx = Int(s), idx >= 0, idx < indexToID.count { return indexToID[idx] }
            }
            return nil
        }

        var edges: [Edge] = []
        edges.reserveCapacity(rawEdges.count)
        var degree: [String: Int] = [:]
        for e in rawEdges {
            guard let s = resolve(e["source"] ?? e["from"]),
                  let t = resolve(e["target"] ?? e["to"]),
                  s != t else { continue }
            let label = (e["label"] as? String) ?? (e["type"] as? String)
                ?? (e["rel"] as? String) ?? (e["relation"] as? String)
            edges.append(Edge(source: s, target: t, label: label))
            degree[s, default: 0] += 1
            degree[t, default: 0] += 1
        }

        // Fold normalised community + degree back into the nodes.
        for i in nodes.indices {
            let id = nodes[i].id
            if let token = rawCommunities[id], let ci = communityIndex[token] { nodes[i].community = ci }
            nodes[i].degree = degree[id] ?? 0
        }

        guard !nodes.isEmpty else { return nil }
        return CodeGraph(nodes: nodes, edges: edges, communityCount: communityCount)
    }
}
