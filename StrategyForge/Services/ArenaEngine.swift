//
//  ArenaEngine.swift
//  StrategyForge
//
//  "Arena": run the SAME task against several providers/models at once and keep the best
//  answer — an alternative to hand-designing roles, for users who'd rather compete models
//  than assign them. Pure fan-out over an injected OneShotRunner (the same primitive the
//  meta-orchestrator and evals use), so it's unit-testable with a mock. Each entrant's
//  failure is captured as its own outcome and never fails the whole arena.
//

import Foundation

/// One competitor in the arena: a provider + the model it runs.
struct ArenaEntrant: Sendable, Identifiable, Equatable {
    let provider: AIProvider
    let model: String
    var id: String { "\(provider.rawValue):\(model)" }
}

/// The result of one entrant's run — either a completion or a captured error.
struct ArenaOutcome: Sendable, Identifiable, Equatable {
    let entrant: ArenaEntrant
    var result: OneShotResult?
    var error: String?
    var id: String { entrant.id }

    var succeeded: Bool { result != nil }
}

enum ArenaEngine {

    /// Run `prompt` against every entrant concurrently. Returns one outcome per entrant,
    /// in the entrants' original order, each isolating its own success/failure.
    static func run(prompt: String,
                    entrants: [ArenaEntrant],
                    cwd: String?,
                    runner: OneShotRunner) async -> [ArenaOutcome] {
        guard !entrants.isEmpty else { return [] }
        let collected = await withTaskGroup(of: ArenaOutcome.self) { group -> [ArenaOutcome] in
            for e in entrants {
                group.addTask {
                    do {
                        let r = try await runner.run(prompt: prompt, provider: e.provider, model: e.model, cwd: cwd)
                        return ArenaOutcome(entrant: e, result: r, error: nil)
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return ArenaOutcome(entrant: e, result: nil, error: message)
                    }
                }
            }
            var out: [ArenaOutcome] = []
            for await o in group { out.append(o) }
            return out
        }
        // Preserve the entrants' order (task-group completion order is nondeterministic).
        return entrants.compactMap { e in collected.first { $0.entrant == e } }
    }

    /// A cheap default winner suggestion when the user hasn't picked one: the cheapest
    /// successful run (ties broken by fewer tokens). Purely a hint — the user decides.
    static func suggestedWinner(_ outcomes: [ArenaOutcome]) -> ArenaOutcome.ID? {
        outcomes
            .filter { $0.succeeded }
            .min { a, b in
                let ca = a.result!.costUSD, cb = b.result!.costUSD
                if ca != cb { return ca < cb }
                return a.result!.tokens < b.result!.tokens
            }?
            .id
    }
}
