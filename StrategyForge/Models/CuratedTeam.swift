//
//  CuratedTeam.swift
//  StrategyForge
//
//  A discoverable team in the team catalog (before import). Mirrors CuratedSkill:
//  a curated entry is either a built-in starter team (resolved locally from the
//  StrategyLibrary — always works, no network) or a community team stored as a
//  `.sfstrategy` document in a GitHub repo (fetched over HTTPS on import). The
//  imported team lands in the user's saved-team library like any other preset.
//

import Foundation

struct CuratedTeam: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let description: String
    let category: String
    let source: Source
    /// Curated entries are vetted by Coral; pasted refs are not.
    var verified: Bool = true

    enum Source: Hashable {
        /// A StrategyLibrary factory key (see `TeamCatalogStore.builtinStrategy`).
        case builtin(String)
        /// A `.sfstrategy` document at repo path (fetched from raw.githubusercontent).
        case github(owner: String, repo: String, ref: String, path: String)
    }

    /// Raw URL of the team's `.sfstrategy` document (nil for built-ins).
    var strategyURL: URL? {
        guard case let .github(owner, repo, ref, path) = source, !path.isEmpty else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref)/\(path)")
    }

    var repoURL: URL? {
        guard case let .github(owner, repo, _, _) = source else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)")
    }

    /// Whether this entry needs a network fetch to import (community teams do).
    var isRemote: Bool {
        if case .github = source { return true }
        return false
    }
}
