//
//  CodeMapDigest.swift
//  StrategyForge
//
//  Turns a parsed CodeGraph (graphify's output) into a COMPACT markdown briefing that
//  Coral injects into an agent's context at the start of a session — so the agent opens
//  with a structural map of the repo (clusters, hub symbols, the seams where modules
//  connect) instead of spending a chunk of its window re-reading files to build that map
//  itself. Mirrors the MemoryDigest pattern: a pure string builder, no side effects.
//
//  It also estimates the token saving, HONESTLY: the digest replaces the cold read of the
//  source files the map covers. We measure the real byte size of those files on disk
//  (÷4 ≈ tokens) as the "cold read" baseline, subtract the digest's own tokens, and label
//  the result an estimate everywhere it surfaces. No fabricated multipliers.
//

import Foundation

enum CodeMapDigest {

    /// An estimate of what injecting the map saves — all figures approximate and labelled
    /// as such in the UI.
    struct Estimate: Equatable {
        var digestTokens: Int      // ~tokens the injected briefing costs
        var coldReadTokens: Int    // ~tokens to read the covered source files instead
        var savedTokens: Int       // max(0, coldRead - digest)
        var savedUSD: Double
    }

    // MARK: - Digest

    /// Compact markdown map of the repo: clusters (named when graphify named them), the
    /// most-connected hub symbols with file:line, and cross-cluster connections. Capped so
    /// it stays a few hundred tokens, not a wall of text.
    static func render(_ graph: CodeGraph, repoName: String) -> String {
        let byID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var byCommunity: [Int: [CodeGraph.Node]] = [:]
        for n in graph.nodes { byCommunity[n.community, default: []].append(n) }

        var s = "# Code map — \(repoName)\n"
        s += "A precomputed structural overview of this repository (generated locally by graphify: deterministic AST parsing + community clustering). Use it to navigate and reason about structure directly, instead of scanning files to rebuild the same map.\n\n"

        // Clusters — largest first, named when available.
        s += "## Clusters (\(graph.communityCount))\n"
        let clusters = byCommunity.sorted { $0.value.count > $1.value.count }.prefix(8)
        for (community, membersRaw) in clusters {
            let members = membersRaw.sorted { $0.degree > $1.degree }
            let name = members.compactMap { $0.communityName }.first ?? "Cluster \(community)"
            let tops = members.prefix(4).map { $0.label }.joined(separator: ", ")
            s += "- **\(name)** (\(members.count)) — \(tops)\n"
        }

        // Hubs — the most-connected symbols, with location.
        let hubs = graph.nodes.filter { $0.degree > 0 }.sorted { $0.degree > $1.degree }.prefix(15)
        if !hubs.isEmpty {
            s += "\n## Key hubs (most-connected)\n"
            for n in hubs {
                let loc = n.file.map { f in n.line.map { "\(f):\($0)" } ?? f }
                s += "- `\(n.label)`" + (loc.map { " — \($0)" } ?? "") + " · \(n.degree) links\n"
            }
        }

        // Seams — a sample of cross-cluster edges (where modules talk to each other).
        var seams: [String] = []
        for e in graph.edges {
            guard let a = byID[e.source], let b = byID[e.target], a.community != b.community else { continue }
            let rel = e.label.map { " (\($0))" } ?? ""
            seams.append("- `\(a.label)` → `\(b.label)`\(rel)")
            if seams.count >= 12 { break }
        }
        if !seams.isEmpty {
            s += "\n## Cross-cluster connections\n" + seams.joined(separator: "\n") + "\n"
        }
        return s
    }

    // MARK: - Estimate

    /// Estimate the saving from injecting `digest` instead of letting the agent cold-read
    /// the source files the map covers. `repoPath` is the folder the node file paths are
    /// relative to. Coarse by design (÷4 chars-per-token), and surfaced with a "~".
    static func estimate(digest: String, graph: CodeGraph, repoPath: String) -> Estimate {
        let digestTokens = max(1, digest.count / 4)

        // Real byte size of the unique files the map references = a defensible "cold read"
        // baseline. Bounded so a huge monorepo can't produce an absurd headline number.
        let fm = FileManager.default
        var seen = Set<String>()
        var bytes = 0
        var scanned = 0
        for node in graph.nodes {
            guard let f = node.file, !f.isEmpty else { continue }
            let path = f.hasPrefix("/") ? f : (repoPath as NSString).appendingPathComponent(f)
            guard seen.insert(path).inserted else { continue }
            if scanned >= 800 { break }
            if let size = (try? fm.attributesOfItem(atPath: path)[.size]) as? Int {
                bytes += size
                scanned += 1
            }
        }
        let coldReadTokens = min(bytes / 4, 400_000)
        let saved = max(0, coldReadTokens - digestTokens)
        let perM = Constants.CostModel.estimatedBlendedFallbackPerM
        let usd = Double(saved) / 1_000_000 * perM
        return Estimate(digestTokens: digestTokens, coldReadTokens: coldReadTokens,
                        savedTokens: saved, savedUSD: usd)
    }
}
