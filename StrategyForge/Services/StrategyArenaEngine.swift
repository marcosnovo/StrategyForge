//
//  StrategyArenaEngine.swift
//  StrategyForge
//
//  "Strategy Arena": run the SAME task against several whole TEAM strategies at once
//  (each possibly multi-provider/multi-model) and keep the best — the agentic sibling of
//  the single-model Arena, and the one only Coral can do because only Coral designs teams.
//
//  Safe by construction: every contestant runs through MetaOrchestrator with a READ-ONLY
//  runner, so no contestant edits the repo — they can't stomp each other and there's no
//  worktree-merge risk. (Code-editing contestants isolated in git worktrees are a later
//  slice.) Transparency is first-class: each contestant streams a fresh progress snapshot
//  (phase, active agents, tokens, cost) as MetaOrchestrator emits events, so a slow run
//  never looks blocked.
//

import Foundation

/// One team in the arena.
struct StrategyContestant: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let strategy: Strategy
}

enum StrategyRunState: String, Sendable, Equatable { case queued, running, done, failed }

/// Live, per-contestant progress — reduced from MetaOrchestrator's event stream.
struct StrategyRunProgress: Sendable, Equatable {
    var state: StrategyRunState = .queued
    var phase: String = ""                 // "plan" | "delegate" | "synthesize"
    var activeRoles: [String] = []         // agents working right now (ordered for stable UI)
    var finishedRoles: [String] = []
    var tokens: Int = 0                     // accumulated across every call
    var costUSD: Double = 0
    var estimated: Bool = false
    var answer: String? = nil
    var error: String? = nil
    var lastNarration: String = ""
}

/// Pure reduction of one MetaEvent into a contestant's progress. Unit-tested.
enum StrategyProgressReducer {
    static func reduce(_ progress: StrategyRunProgress, _ event: MetaEvent) -> StrategyRunProgress {
        var p = progress
        if p.state == .queued { p.state = .running }
        switch event {
        case .phase(let ph):
            p.phase = ph; p.lastNarration = ph
        case .rolePlanned:
            break   // instance-count hint — arena progress tracks roles as they start
        case .roleStarted(let role, _, _, let task):
            if !p.activeRoles.contains(role) { p.activeRoles.append(role) }
            p.lastNarration = task.isEmpty ? role : "\(role): \(task)"
        case .roleActivity(let role, let title, let detail):
            // Live tool step — surface it as the contestant's latest narration line.
            p.lastNarration = detail.map { "\(role): \(title) \($0)" } ?? "\(role): \(title)"
        case .roleNarration(let role, let text):
            p.lastNarration = "\(role): \(text)"
        case .authRequired(let provider):
            p.lastNarration = "\(provider.displayName): needs re-login"
        case .roleFile:
            break   // file edits don't change arena progress state
        case .roleFinished(let role, _):
            p.activeRoles.removeAll { $0 == role }
            if !p.finishedRoles.contains(role) { p.finishedRoles.append(role) }
        case .roleFailed(let role, let message):
            p.activeRoles.removeAll { $0 == role }
            p.lastNarration = "\(role): \(message)"
        case .usage(let tokens, let cost, let estimated):
            // MetaOrchestrator emits usage PER CALL — accumulate for the run total.
            p.tokens += tokens; p.costUSD += cost
            if estimated { p.estimated = true }
        case .assistantText(let text):
            p.answer = text
        case .finished:
            p.state = .done; p.activeRoles = []
        case .failed(let message):
            p.state = .failed; p.error = message; p.activeRoles = []
        }
        return p
    }
}

/// Thread-safe progress holder — MetaOrchestrator emits events from concurrent worker
/// tasks, so the reduce must be serialized.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = StrategyRunProgress()
    func apply(_ event: MetaEvent) -> StrategyRunProgress {
        lock.lock(); defer { lock.unlock() }
        progress = StrategyProgressReducer.reduce(progress, event)
        return progress
    }
    func set(_ p: StrategyRunProgress) { lock.lock(); progress = p; lock.unlock() }
    func get() -> StrategyRunProgress { lock.lock(); defer { lock.unlock() }; return progress }
}

enum StrategyArenaEngine {

    /// Run every contestant's strategy on `task` concurrently (read-only via `runner`),
    /// streaming a fresh progress snapshot per contestant through `onUpdate`. Returns the
    /// final snapshots keyed by contestant id. One contestant failing never sinks the arena.
    static func run(task: String,
                    cwd: String?,
                    contestants: [StrategyContestant],
                    runner: OneShotRunner,
                    onUpdate: @escaping @Sendable (String, StrategyRunProgress) -> Void) async -> [String: StrategyRunProgress] {
        guard !contestants.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, StrategyRunProgress).self) { group in
            for c in contestants {
                group.addTask {
                    let box = ProgressBox()
                    box.set(StrategyRunProgress(state: .running))
                    onUpdate(c.id, box.get())

                    let answer = await MetaOrchestrator.run(
                        strategy: c.strategy, task: task, cwd: cwd, runner: runner
                    ) { event in
                        onUpdate(c.id, box.apply(event))
                    }

                    // Guarantee a terminal state even if the engine returned without a
                    // .finished/.failed event.
                    var final = box.get()
                    if final.state != .done && final.state != .failed {
                        if answer != nil {
                            final.state = .done
                            if final.answer == nil { final.answer = answer }
                        } else {
                            final.state = .failed
                            if final.error == nil { final.error = "The team produced no result." }
                        }
                        final.activeRoles = []
                        box.set(final)
                        onUpdate(c.id, final)
                    }
                    return (c.id, box.get())
                }
            }
            var out: [String: StrategyRunProgress] = [:]
            for await (id, p) in group { out[id] = p }
            return out
        }
    }

    /// Winner hint for finished teams: cheapest successful run (ties → fewer tokens).
    /// Purely a suggestion — the user decides (agentic "best" is a judgment, not a metric).
    static func suggestedWinner(_ finals: [String: StrategyRunProgress]) -> String? {
        finals
            .filter { $0.value.state == .done && $0.value.answer?.isEmpty == false }
            .min { a, b in
                if a.value.costUSD != b.value.costUSD { return a.value.costUSD < b.value.costUSD }
                return a.value.tokens < b.value.tokens
            }?
            .key
    }
}
