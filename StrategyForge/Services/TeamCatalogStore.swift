//
//  TeamCatalogStore.swift
//  StrategyForge
//
//  The team catalog engine (v1): a curated Git-backed marketplace of agent teams,
//  mirroring SkillStore. Discover a starter team (built-in, resolved locally) or a
//  community team (a `.sfstrategy` document in a GitHub repo, fetched over HTTPS and
//  decoded with StrategyPackage). Import drops the team into the saved-team library;
//  no backend, no API keys — the catalog is just a repo the app reads.
//
//  Real execution metrics (avg cost, verifier PASS rate) are a later, backend-backed
//  step; v1 is the discover + one-click import that today's ecosystem lacks.
//

import Foundation
import Observation

@Observable
@MainActor
final class TeamCatalogStore {
    static let shared = TeamCatalogStore()

    enum FetchError: LocalizedError {
        case badRef, network(String), empty, notATeam
        var errorDescription: String? {
            switch self {
            case .badRef:    return "That doesn't look like owner/repo[@ref]#path/to/team.sfstrategy."
            case .network(let m): return m
            case .empty:     return "Nothing found at that reference."
            case .notATeam:  return "That file isn't a valid Coral team (.sfstrategy)."
            }
        }
    }

    // MARK: - Resolve to a Strategy

    /// Resolve a curated entry to a concrete strategy — locally for built-ins, over
    /// the network for community teams.
    func resolve(_ team: CuratedTeam) async throws -> Strategy {
        switch team.source {
        case .builtin(let key):
            guard let s = Self.builtinStrategy(key) else { throw FetchError.empty }
            return s
        case .github:
            guard let url = team.strategyURL else { throw FetchError.badRef }
            return try await fetchStrategy(url)
        }
    }

    /// Resolve a pasted "owner/repo[@ref]#path/to/team.sfstrategy" reference. The
    /// path must point at a `.sfstrategy` document.
    func resolve(githubRef ref: String) async throws -> Strategy {
        try await fetchStrategy(Self.rawURL(fromRef: ref))
    }

    private func fetchStrategy(_ url: URL) async throws -> Strategy {
        let data = try await fetchData(url)
        do { return try StrategyPackage.import(data) }
        catch { throw FetchError.notATeam }
    }

    // MARK: - GitHub ref → raw URL (pure, testable)

    /// Build the raw.githubusercontent URL for a "owner/repo[@ref]#path" reference.
    /// `@ref` defaults to `main`. The `#path` (or a third `/`-segment) must be the
    /// repo-relative path to the `.sfstrategy` file.
    static func rawURL(fromRef ref: String) throws -> URL {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://github.com/", with: "")
        var rest = trimmed, path = "", gitRef = "main"
        if let hash = rest.firstIndex(of: "#") {
            path = String(rest[rest.index(after: hash)...]); rest = String(rest[..<hash])
        }
        if let at = rest.firstIndex(of: "@") {
            gitRef = String(rest[rest.index(after: at)...]); rest = String(rest[..<at])
        }
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw FetchError.badRef }
        let owner = parts[0], repo = parts[1]
        if path.isEmpty, parts.count > 2 { path = parts[2...].joined(separator: "/") }
        guard !path.isEmpty else { throw FetchError.badRef }
        guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(gitRef)/\(path)")
        else { throw FetchError.badRef }
        return url
    }

    private func fetchData(_ url: URL) async throws -> Data {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 { throw FetchError.empty }
            guard !data.isEmpty else { throw FetchError.empty }
            return data
        } catch let e as FetchError { throw e }
        catch { throw FetchError.network(error.localizedDescription) }
    }

    // MARK: - Built-in starter teams (resolved from the StrategyLibrary)

    /// Map a curated built-in key to its StrategyLibrary factory.
    static func builtinStrategy(_ key: String) -> Strategy? {
        switch key {
        case "orchestratorWorkers":          return StrategyLibrary.orchestratorWorkers()
        case "executorAdvisor":              return StrategyLibrary.executorAdvisor()
        case "scoutAct":                     return StrategyLibrary.scoutAct()
        case "triageRouter":                 return StrategyLibrary.triageRouter()
        case "rootCauseDebugging":           return StrategyLibrary.rootCauseDebugging()
        case "plannerImplementersReviewer":  return StrategyLibrary.plannerImplementersReviewer()
        case "domainSpecialists":            return StrategyLibrary.domainSpecialists()
        case "researchFanout":               return StrategyLibrary.researchFanout()
        case "debateConsensus":              return StrategyLibrary.debateConsensus()
        case "sparring":                     return StrategyLibrary.sparring()
        case "solo":                         return StrategyLibrary.solo()
        default:                             return nil
        }
    }

    // MARK: - Curated marketplace (bundled; a hosted index can replace this later)

    /// Starter teams shipped with the app + a home for community entries. Built-ins
    /// give the catalog immediate, proven content ("start from a strategy, not a
    /// blank page"); `.github` entries point at `.sfstrategy` files in a catalog repo.
    let curated: [CuratedTeam] = [
        .init(slug: "fanout", name: "Orchestrator + Workers",
              description: "An orchestrator fans a task out to parallel workers — the workhorse for broad, splittable work.",
              category: "General", source: .builtin("orchestratorWorkers")),
        .init(slug: "planner-reviewer", name: "Planner → Implementers → Reviewer",
              description: "Plan first, implement in parallel, then a read-only reviewer checks the result.",
              category: "Delivery", source: .builtin("plannerImplementersReviewer")),
        .init(slug: "root-cause", name: "Root-cause Debugging",
              description: "Reproduce, isolate and fix a failure methodically.",
              category: "Debugging", source: .builtin("rootCauseDebugging")),
        .init(slug: "research", name: "Research Fan-out",
              description: "An orchestrator plus read-only researchers exploring in parallel.",
              category: "Research", source: .builtin("researchFanout")),
        .init(slug: "domain", name: "Domain Specialists",
              description: "Backend / frontend / tests / security / docs specialists, routed by an orchestrator.",
              category: "Delivery", source: .builtin("domainSpecialists")),
        .init(slug: "sparring", name: "Sparring",
              description: "One agent builds while a challenger stress-tests every proposal.",
              category: "Quality", source: .builtin("sparring")),
    ]
}
