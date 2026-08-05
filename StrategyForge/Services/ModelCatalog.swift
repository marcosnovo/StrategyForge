//
//  ModelCatalog.swift
//  StrategyForge
//
//  A tiny, self-updating model catalog. Providers rotate their model line-ups roughly
//  monthly (GPT-5.5 → 5.6 Terra/Luna, Gemini 2.5 → 3, …), faster than we ship app
//  releases — so instead of ONLY hardcoding the list, Coral fetches a small JSON catalog
//  from the (public) Coral repo at launch and merges it over the built-in defaults. That
//  lets new models be ADDED and deprecated ones REMOVED without an app update, while the
//  compiled-in `AIProvider.builtInModels` remains the always-works fallback (offline, or
//  before the first fetch). Best-effort and non-fatal by design.
//
//  The remote file is `models.json` at the repo root; edit it to change the catalog for
//  every user on their next launch. Shape (a "providers" map so a top-level "_comment" can
//  sit beside it):
//    { "providers": { "openai": [ {"id","displayName","tierKey"}, … ], "gemini": [ … ] } }
//  A provider omitted from "providers" keeps its built-in list.
//

import Foundation

enum ModelCatalog {

    /// The repo-hosted catalog (raw GitHub). Public repo, so no auth needed.
    static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/marcosnovo/StrategyForge/main/models.json")!

    // Lock-guarded snapshot so `AIProvider.models` (nonisolated, read from anywhere) is safe.
    private static let lock = NSLock()
    private static var overrides: [String: [ProviderModel]] = [:]   // keyed by AIProvider.rawValue

    /// The effective model list for a provider: the fetched override when present, else the
    /// compiled-in default. Never empty (an empty/blank override is ignored).
    static func models(for provider: AIProvider) -> [ProviderModel] {
        lock.lock(); defer { lock.unlock() }
        if let o = overrides[provider.rawValue], !o.isEmpty { return o }
        return provider.builtInModels
    }

    /// Fetch the remote catalog (via the on-disk HTTP cache, so it's instant/offline on later
    /// launches) and merge it over the built-ins. Silently keeps the built-ins on any failure
    /// — a bad network or a malformed file must never leave the pickers empty.
    private struct Catalog: Decodable { let providers: [String: [ProviderModel]] }

    static func refresh() async {
        guard let data = try? await HTTPCache.data(from: remoteURL),
              let decoded = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return }
        var next: [String: [ProviderModel]] = [:]
        for (key, list) in decoded.providers where AIProvider(rawValue: key) != nil && !list.isEmpty {
            next[key] = list
        }
        guard !next.isEmpty else { return }
        apply(next)
        let summary = next.map { "\($0.key)×\($0.value.count)" }.sorted().joined(separator: ", ")
        DiagnosticsLog.record("model catalog updated from remote: \(summary)", level: "INFO")
    }

    /// Synchronous, lock-guarded snapshot swap (kept out of the async `refresh` so the lock is
    /// never held across a suspension point).
    private static func apply(_ next: [String: [ProviderModel]]) {
        lock.lock(); overrides = next; lock.unlock()
    }
}
