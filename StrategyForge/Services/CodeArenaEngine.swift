//
//  CodeArenaEngine.swift
//  StrategyForge
//
//  The write-capable arena: several contestants do the SAME coding task at once, each in
//  its OWN isolated git worktree (a fresh branch off HEAD), and we compare the diffs.
//
//  A contestant is either a single PROVIDER (one write-capable model editing) or a whole
//  TEAM strategy (materialized into the worktree as `.claude/agents` + `CLAUDE.md`, then
//  run as a native `claude` session whose orchestrator delegates to its subagents — real
//  multi-agent editing). For teams the scaffolding is committed as a baseline first, so
//  the compared diff is the team's actual code work, not its setup files.
//
//  Safe by design: the user's working tree is NEVER touched during the run — every edit
//  lands in a separate app-owned worktree on its own branch. Only when the user applies a
//  winner do we merge that one branch back; the losing worktrees + branches are removed.
//

import Foundation

/// One entry in the code arena.
struct CodeContestant: Sendable, Identifiable, Equatable {
    let id: String
    let label: String            // "Claude" or a team name
    let provider: AIProvider     // the runtime + avatar (teams run native on .claude)
    let model: String
    /// nil → a single provider one-shot; set → write the team's files, run it natively.
    let strategy: Strategy?

    static func provider(_ p: AIProvider, model: String) -> CodeContestant {
        CodeContestant(id: "p:\(p.rawValue):\(model)", label: p.displayName, provider: p, model: model, strategy: nil)
    }
    static func team(id: String, name: String, strategy: Strategy) -> CodeContestant {
        // Teams run through the native `claude` session (their subagents edit files).
        let orch = strategy.orchestrator
        let model = (orch?.provider == .claude ? orch?.model.rawValue : nil) ?? ""
        return CodeContestant(id: "t:\(id)", label: name, provider: .claude, model: model, strategy: strategy)
    }
}

/// One contestant's write-capable run + the diff it produced.
struct CodeArenaOutcome: Sendable, Equatable, Identifiable {
    let contestant: CodeContestant
    var id: String { contestant.id }
    var state: StrategyRunState = .queued
    var diff: String = ""
    var changedFiles: Int = 0
    var tokens: Int = 0
    var costUSD: Double = 0
    var estimated: Bool = false
    var branch: String = ""
    var worktreePath: String = ""
    var error: String?

    var producedChanges: Bool { !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum CodeArenaEngine {

    /// Parent dir for arena worktrees — app-owned scratch, never inside the user's repo.
    private static func arenaRoot() -> URL {
        let dir = AppPaths.supportDirectory().appendingPathComponent("arena-worktrees", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Run every contestant on `task` against `repo`, each isolated in its own worktree.
    /// `runner` MUST be write-capable. `binary` is the `claude` binary for materializing +
    /// running team contestants. One contestant failing never sinks the arena. Worktrees
    /// are LEFT in place for diff display + possible apply.
    static func run(task: String,
                    repo: String,
                    contestants: [CodeContestant],
                    binary: String = "claude",
                    runner: OneShotRunner,
                    onUpdate: @escaping @Sendable (String, CodeArenaOutcome) -> Void) async -> [String: CodeArenaOutcome] {
        guard !contestants.isEmpty else { return [:] }
        let root = arenaRoot()
        return await withTaskGroup(of: (String, CodeArenaOutcome).self) { group in
            for c in contestants {
                group.addTask {
                    var outcome = CodeArenaOutcome(contestant: c, state: .running)
                    let token = UUID().uuidString.prefix(8)
                    let branch = "arena/\(c.provider.rawValue)-\(token)"
                    let path = root.appendingPathComponent("\(c.provider.rawValue)-\(token)", isDirectory: true).path
                    outcome.branch = branch; outcome.worktreePath = path
                    onUpdate(c.id, outcome)

                    // 1) Isolated worktree off HEAD.
                    let add = await CodeGit.addWorktree(repo: repo, path: path, branch: branch)
                    guard add.ok else {
                        outcome.state = .failed
                        outcome.error = "Couldn't create an isolated worktree: \(add.out.prefix(160))"
                        onUpdate(c.id, outcome); return (c.id, outcome)
                    }

                    // 2) For a TEAM: materialize its .claude files, then commit them as a
                    //    baseline so the compared diff is the team's code work, not setup.
                    if let strategy = c.strategy {
                        do {
                            _ = try StrategyWriter(repoURL: URL(fileURLWithPath: path), binary: binary)
                                .write(strategy: strategy)
                        } catch {
                            outcome.state = .failed
                            outcome.error = "Couldn't write the team's files: \(error.localizedDescription)"
                            onUpdate(c.id, outcome); return (c.id, outcome)
                        }
                        _ = await CodeGit.commitAll(dir: path, message: "arena: team setup (\(c.label))")
                    }

                    // 3) Run the contestant, write-capable, inside the worktree.
                    do {
                        let r = try await runner.run(prompt: task, provider: c.provider, model: c.model, cwd: path)
                        outcome.tokens = r.tokens; outcome.costUSD = r.costUSD; outcome.estimated = r.estimated
                    } catch {
                        outcome.state = .failed
                        outcome.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        onUpdate(c.id, outcome); return (c.id, outcome)
                    }

                    // 4) Capture the diff (incl. new untracked files) BEFORE committing.
                    outcome.diff = await CodeGit.fullDiff(repo: path) ?? ""
                    outcome.changedFiles = await CodeGit.changedFiles(repo: path).count
                    // 5) Commit the work so a winner can be merged later.
                    _ = await CodeGit.commitAll(dir: path, message: "arena: \(c.label) — \(task.prefix(60))")

                    outcome.state = .done
                    onUpdate(c.id, outcome)
                    return (c.id, outcome)
                }
            }
            var out: [String: CodeArenaOutcome] = [:]
            for await (id, o) in group { out[id] = o }
            return out
        }
    }

    /// Merge the winner's branch back into the user's working tree, then tear down every
    /// arena worktree + loser branch.
    static func applyWinner(repo: String, winner: CodeArenaOutcome,
                            all: [CodeArenaOutcome]) async -> (ok: Bool, out: String) {
        let merge = await CodeGit.mergeNoFF(repo: repo, branch: winner.branch,
                                            message: "Arena winner: \(winner.contestant.label)")
        for o in all { await CodeGit.removeWorktree(repo: repo, path: o.worktreePath) }
        for o in all where o.id != winner.id || merge.ok { await CodeGit.deleteBranch(repo: repo, name: o.branch) }
        return merge
    }

    /// Discard everything — remove every arena worktree and delete every branch. Leaves
    /// the user's working tree exactly as it was.
    static func cleanup(repo: String, all: [CodeArenaOutcome]) async {
        for o in all {
            await CodeGit.removeWorktree(repo: repo, path: o.worktreePath)
            await CodeGit.deleteBranch(repo: repo, name: o.branch)
        }
    }
}
