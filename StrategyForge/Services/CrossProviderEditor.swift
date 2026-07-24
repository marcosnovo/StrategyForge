//
//  CrossProviderEditor.swift
//  StrategyForge
//
//  Cross-provider file editing with per-line provenance. A team whose roles run on
//  DIFFERENT providers (a Gemini planner, a Codex implementer, a Claude reviewer…) edits
//  the SAME worktree in SEQUENCE — one worker at a time, so there are no concurrent-write
//  conflicts — and after each worker we re-attribute every changed line to whoever just
//  wrote it (via the pure, tested LineAttributor). The result is a diff where each line is
//  credited to the provider/model that authored it: cross-provider line provenance, the
//  step the native path couldn't do (its cross-provider workers returned text, not edits).
//
//  Meant to run inside an already-isolated git worktree (see CodeArenaEngine), so it never
//  touches the user's tree.
//

import Foundation

/// A file's authorship after the sequence: which team members touched it, in order.
struct FileProvenance: Sendable, Equatable, Identifiable {
    let file: String
    var authors: [EditProvenance]     // distinct, in first-touch order
    var id: String { file }
}

struct CrossProviderResult: Sendable, Equatable {
    var diff: String = ""
    var perFile: [FileProvenance] = []
    var tokens: Int = 0
    var costUSD: Double = 0
    var estimated: Bool = false
    /// Per-line authorship, keyed by repo-relative file → one author per line of the final
    /// file (nil where unknown). Available for a richer per-line diff view.
    var lineAuthors: [String: [EditProvenance?]] = [:]
    var error: String?
}

enum CrossProviderEditor {

    /// Whether a strategy needs this path: any role runs on a non-Claude provider.
    static func isCrossProvider(_ strategy: Strategy) -> Bool {
        strategy.roles.contains { $0.provider != .claude }
    }

    /// The team members who do the editing, in run order: the subagents, or the
    /// orchestrator alone for a solo config.
    static func editors(_ strategy: Strategy) -> [AgentRole] {
        let subs = strategy.subagentRoles
        if !subs.isEmpty { return subs }
        return strategy.orchestrator.map { [$0] } ?? []
    }

    /// Run each editor in sequence inside `worktree`, attributing lines as we go.
    /// `runner` MUST be write-capable. `onWorker` fires before each worker starts, so the
    /// UI can show who's editing now.
    static func run(task: String,
                    worktree: String,
                    strategy: Strategy,
                    runner: OneShotRunner,
                    onWorker: @escaping @Sendable (EditProvenance) -> Void) async -> CrossProviderResult {
        var result = CrossProviderResult()
        // file → (current lines, per-line authors) carried across workers.
        var files: [String: (lines: [String], authors: [EditProvenance?])] = [:]
        var order: [String] = []                 // first-touch order of files
        var touched: [String: [EditProvenance]] = [:]

        let team = editors(strategy)
        guard !team.isEmpty else { result.error = "This team has no agents to run."; return result }

        for role in team {
            let author = EditProvenance(
                agent: role.isOrchestrator ? nil : role.name,
                model: role.modelDisplayName, provider: role.provider)
            onWorker(author)

            let prompt = workerPrompt(task: task, role: role, isSolo: team.count == 1)
            do {
                let r = try await runner.run(prompt: prompt, provider: role.provider,
                                             model: MetaOrchestrator.modelID(for: role), cwd: worktree)
                result.tokens += r.tokens; result.costUSD += r.costUSD
                if r.estimated { result.estimated = true }
            } catch {
                // One worker failing doesn't abort the sequence — the next may still work.
                continue
            }

            // Re-attribute every changed file after this worker's edits.
            for changed in await CodeGit.changedFiles(repo: worktree) {
                let path = changed.path
                let url = URL(fileURLWithPath: worktree).appendingPathComponent(path)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let newLines = text.components(separatedBy: "\n")
                let prev = files[path] ?? (lines: [], authors: [])
                let authors = LineAttributor.attribute(old: prev.lines, oldAuthors: prev.authors,
                                                       new: newLines, author: author)
                files[path] = (newLines, authors)
                if touched[path] == nil { order.append(path) }
                touched[path, default: []].append(author)
            }
        }

        result.diff = await CodeGit.fullDiff(repo: worktree) ?? ""
        result.lineAuthors = files.mapValues { $0.authors }
        result.perFile = order.map { file in
            FileProvenance(file: file, authors: distinct(touched[file] ?? []))
        }
        return result
    }

    // MARK: - Helpers

    private static func workerPrompt(task: String, role: AgentRole, isSolo: Bool) -> String {
        if isSolo {
            return "\(task)\n\nEdit the files in this repository directly to complete the task."
        }
        return """
        You are the "\(role.name)" agent on a team working this task:

        \(task)

        Do YOUR part now by editing the files in this repository directly. Build on any \
        changes already present from teammates; don't undo their work. Keep your edits \
        focused on your role.
        """
    }

    /// Distinct authors preserving first-seen order.
    private static func distinct(_ authors: [EditProvenance]) -> [EditProvenance] {
        var seen = Set<EditProvenance>(); var out: [EditProvenance] = []
        for a in authors where seen.insert(a).inserted { out.append(a) }
        return out
    }
}
