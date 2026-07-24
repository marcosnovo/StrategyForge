//
//  CodeArenaEngine.swift
//  StrategyForge
//
//  The write-capable arena: several providers do the SAME coding task at once, each in
//  its OWN isolated git worktree (a fresh branch off HEAD), and we compare the diffs.
//
//  Safe by design: the user's working tree is NEVER touched during the run — every edit
//  lands in a separate worktree on its own branch. Only when the user explicitly applies a
//  winner do we merge that one branch back; the losing worktrees + branches are removed.
//  So a runaway agent can, at worst, dirty a throwaway worktree we delete.
//

import Foundation

/// One contestant's write-capable run + the diff it produced.
struct CodeArenaOutcome: Sendable, Equatable, Identifiable {
    let entrant: ArenaEntrant
    var id: String { entrant.id }
    var state: StrategyRunState = .queued
    var diff: String = ""
    var changedFiles: Int = 0
    var tokens: Int = 0
    var costUSD: Double = 0
    var estimated: Bool = false
    /// The branch holding this contestant's work (for apply/cleanup).
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

    /// Run every entrant on `task` against `repo`, each isolated in its own worktree.
    /// Streams a fresh outcome per entrant through `onUpdate`. `runner` MUST be
    /// write-capable (readOnly == false) for edits to land. One entrant failing never
    /// sinks the arena. Returns final outcomes keyed by entrant id (worktrees are LEFT in
    /// place for diff display + possible apply — call `cleanup`/`applyWinner` after).
    static func run(task: String,
                    repo: String,
                    entrants: [ArenaEntrant],
                    runner: OneShotRunner,
                    onUpdate: @escaping @Sendable (String, CodeArenaOutcome) -> Void) async -> [String: CodeArenaOutcome] {
        guard !entrants.isEmpty else { return [:] }
        let root = arenaRoot()
        return await withTaskGroup(of: (String, CodeArenaOutcome).self) { group in
            for e in entrants {
                group.addTask {
                    var outcome = CodeArenaOutcome(entrant: e, state: .running)
                    let token = UUID().uuidString.prefix(8)
                    let branch = "arena/\(e.provider.rawValue)-\(token)"
                    let path = root.appendingPathComponent("\(e.provider.rawValue)-\(token)", isDirectory: true).path
                    outcome.branch = branch; outcome.worktreePath = path
                    onUpdate(e.id, outcome)

                    // 1) Isolated worktree off HEAD.
                    let add = await CodeGit.addWorktree(repo: repo, path: path, branch: branch)
                    guard add.ok else {
                        outcome.state = .failed
                        outcome.error = "Couldn't create an isolated worktree: \(add.out.prefix(160))"
                        onUpdate(e.id, outcome); return (e.id, outcome)
                    }

                    // 2) Run the contestant, write-capable, inside the worktree.
                    do {
                        let r = try await runner.run(prompt: task, provider: e.provider, model: e.model, cwd: path)
                        outcome.tokens = r.tokens; outcome.costUSD = r.costUSD; outcome.estimated = r.estimated
                    } catch {
                        outcome.state = .failed
                        outcome.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        onUpdate(e.id, outcome); return (e.id, outcome)
                    }

                    // 3) Capture the diff (incl. new untracked files) BEFORE committing.
                    outcome.diff = await CodeGit.fullDiff(repo: path) ?? ""
                    outcome.changedFiles = await CodeGit.changedFiles(repo: path).count
                    // 4) Commit into the branch so a winner can be merged later (a no-op
                    //    commit when nothing changed just leaves the branch at HEAD).
                    _ = await CodeGit.commitAll(dir: path, message: "arena: \(e.provider.displayName) — \(task.prefix(60))")

                    outcome.state = .done
                    onUpdate(e.id, outcome)
                    return (e.id, outcome)
                }
            }
            var out: [String: CodeArenaOutcome] = [:]
            for await (id, o) in group { out[id] = o }
            return out
        }
    }

    /// Merge the winner's branch back into the user's working tree (no-ff so the arena
    /// origin stays visible), then tear down every arena worktree + loser branch.
    static func applyWinner(repo: String, winner: CodeArenaOutcome,
                            all: [CodeArenaOutcome]) async -> (ok: Bool, out: String) {
        let merge = await CodeGit.mergeNoFF(
            repo: repo, branch: winner.branch,
            message: "Arena winner: \(winner.entrant.provider.displayName)")
        // Whatever the merge outcome, remove the worktrees; keep the winner branch only if
        // the merge failed (so the user can resolve it by hand).
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
