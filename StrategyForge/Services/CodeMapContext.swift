//
//  CodeMapContext.swift
//  StrategyForge
//
//  The bridge between the Map feature and the agents: when a chat/Code session starts on a
//  repo that has a graphify graph, Coral injects a compact map digest into the first turn
//  (see ChatViewModel.send) so the agent opens with structure instead of re-reading files.
//  This holds the per-repo graph cache (by mtime, so a rebuilt map is picked up) and a
//  running per-app-session ledger of the ESTIMATED token/cost saving, which the Usage and
//  Map surfaces display next to the Claude usage %.
//

import Foundation

@MainActor
@Observable
final class CodeMapContext {
    static let shared = CodeMapContext()

    struct Injection { var preamble: String; var estimate: CodeMapDigest.Estimate }

    // Running ledger for this app session (reset only on relaunch).
    private(set) var sessionSavedTokens = 0
    private(set) var sessionSavedUSD = 0.0
    private(set) var sessionInjections = 0
    private(set) var lastRepoName: String?

    private var cache: [String: (mtime: Date, graph: CodeGraph)] = [:]

    /// The injection for a repo that has a graphify graph, else nil (no graph → no overhead,
    /// nothing injected). Pure: does not touch the ledger.
    func injection(forRepo repoPath: String) -> Injection? {
        guard let graph = graph(forRepo: repoPath) else { return nil }
        let name = URL(fileURLWithPath: repoPath).lastPathComponent
        let digest = CodeMapDigest.render(graph, repoName: name)
        let est = CodeMapDigest.estimate(digest: digest, graph: graph, repoPath: repoPath)
        return Injection(preamble: digest, estimate: est)
    }

    /// Estimate for a repo without recording it — for the Map header chip.
    func estimate(forRepo repoPath: String) -> CodeMapDigest.Estimate? {
        injection(forRepo: repoPath)?.estimate
    }

    /// Record that a session injected the map for `repoName`, accumulating the saving.
    func record(_ inj: Injection, repoName: String) {
        sessionSavedTokens += inj.estimate.savedTokens
        sessionSavedUSD += inj.estimate.savedUSD
        sessionInjections += 1
        lastRepoName = repoName
    }

    // MARK: - Graph cache

    private func graph(forRepo repoPath: String) -> CodeGraph? {
        guard !repoPath.isEmpty else { return nil }
        let jsonPath = (repoPath as NSString).appendingPathComponent("graphify-out/graph.json")
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: jsonPath),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        if let cached = cache[repoPath], cached.mtime == mtime { return cached.graph }
        if let size = attrs[.size] as? Int, size > 12_000_000 { return nil }   // don't parse a huge graph on the main actor
        guard let data = fm.contents(atPath: jsonPath),
              let g = CodeGraph.parse(data), !g.isEmpty else { return nil }
        cache[repoPath] = (mtime, g)
        return g
    }
}
