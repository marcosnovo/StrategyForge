//
//  CodeGit.swift
//  StrategyForge
//
//  Tiny git helper for Code Mode: compute a unified diff for a file (what changed
//  vs the last commit) and parse it into rendered lines. Runs `git` as a subprocess
//  off the main thread. Returns nil when the folder isn't a git repo or git isn't
//  available — callers then fall back to showing the plain file.
//

import Foundation

struct DiffLine: Identifiable, Hashable {
    enum Kind { case hunk, add, del, context }
    /// Stable identity = position in the parsed diff, so re-parsing an unchanged diff
    /// yields the same ids and SwiftUI reuses rows instead of rebuilding them all.
    let id: Int
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
}

enum CodeGit {

    /// The `git` executable, if present.
    private static func gitPath() -> String? {
        let fm = FileManager.default
        for p in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: p) {
            return p
        }
        return ClaudeRunner.resolveBinary("git")
    }

    /// Unified diff of `file` vs HEAD, parsed. nil if not a repo / no git / no diff.
    nonisolated static func diff(repo: String, file: String) async -> [DiffLine]? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            let out = run(git, ["-C", repo, "diff", "--no-color", "HEAD", "--", file])
            guard let out, !out.isEmpty else { return nil }
            return parse(out)
        }.value
    }

    /// The WHOLE uncommitted diff as raw unified-diff text (nil if none / not a repo):
    /// tracked changes (`git diff HEAD`) PLUS each untracked file diffed against
    /// /dev/null — never-staged new files (the typical agent output) are invisible to
    /// `diff HEAD` but WILL be committed by the default `add -A` commit path, so the
    /// automated diff reviewer must see them too.
    nonisolated static func fullDiff(repo: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            var pieces: [String] = []
            // Tracked changes (index + working tree vs HEAD). This fails on an unborn
            // HEAD — treat that as "no tracked changes" and still report untracked files.
            if let tracked = run(git, ["-C", repo, "diff", "--no-color", "HEAD"]),
               !tracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pieces.append(tracked)
            }
            // Untracked files, .gitignore honored — the same set `add -A` would commit.
            let untracked = runResult(git, ["-C", repo, "-c", "core.quotePath=false",
                                            "ls-files", "--others", "--exclude-standard", "-z"])
            if untracked.ok {
                // Cap what one untracked file can contribute: a huge generated or
                // vendored file would balloon the reviewer prompt far past useful
                // size (and spawn an expensive diff) without improving the review —
                // note it with a stub hunk instead so it's still visibly new.
                let maxFileBytes = 256 * 1024
                for path in untracked.out.split(separator: "\0", omittingEmptySubsequences: true) {
                    let rel = String(path)
                    let abs = (repo as NSString).appendingPathComponent(rel)
                    let size = (try? FileManager.default.attributesOfItem(atPath: abs))?[.size] as? Int ?? 0
                    if size > maxFileBytes {
                        pieces.append("diff --git a/\(rel) b/\(rel)\nnew file, \(size) bytes — too large to inline for review\n")
                        continue
                    }
                    // `--no-index` exits 1 when the files differ — that's success here,
                    // so consult the raw status instead of run()/runResult. Binary files
                    // yield a one-line "Binary files … differ", never raw bytes.
                    let r = runStatus(git, ["-C", repo, "diff", "--no-color", "--no-index",
                                            "--", "/dev/null", rel])
                    if r.status == 0 || r.status == 1, !r.out.isEmpty { pieces.append(r.out) }
                }
            }
            let out = pieces.joined()
            return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : out
        }.value
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let r = runResult(path, args)
        // On failure the (merged) output is an error message, not diff/branch data —
        // return nil so callers don't parse git errors as content.
        return r.ok ? r.out : nil
    }

    /// Run git and return whether it succeeded plus combined output.
    private static func runResult(_ path: String, _ args: [String]) -> (ok: Bool, out: String) {
        let r = runStatus(path, args)
        return (r.status == 0, r.out)
    }

    /// Run git and return the raw exit status plus combined output — for commands where
    /// nonzero isn't failure (`diff --no-index` exits 1 to mean "files differ").
    private static func runStatus(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        // Never let git block on an interactive prompt (a repo needing credentials/askpass
        // would hang readToEnd forever): no stdin, and disable any terminal/askpass prompts.
        p.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_ASKPASS"] = "/usr/bin/true"; env["GCM_INTERACTIVE"] = "never"
        p.environment = env
        do { try p.run() } catch { return (-1, "git \(args.joined(separator: " ")) failed") }
        // Stability: register for kill-on-quit + a watchdog so a wedged git (huge diff, stalled
        // FS, credential hang) can't hang the task or survive as an orphan process.
        LiveProcesses.register(p)
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        LiveProcesses.deregister(p)
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - Write operations (Code Mode git panel)

    /// Current branch name (nil if not a repo / no git).
    nonisolated static func currentBranch(repo: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            let r = runResult(git, ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"])
            let name = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.ok && !name.isEmpty ? name : nil
        }.value
    }

    /// The working branch plus its +insertions / −deletions against the repo's
    /// default branch — what a PR would show — including uncommitted work.
    struct BranchStat: Sendable, Equatable {
        var branch: String
        var base: String
        var insertions: Int
        var deletions: Int
        var isOnBase: Bool { branch == base }
    }

    nonisolated static func branchStat(repo: String) async -> BranchStat? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            let branchR = runResult(git, ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"])
            let branch = branchR.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard branchR.ok, !branch.isEmpty else { return nil }
            // Resolve the default branch from origin/HEAD (fallback: main).
            var base = "main"
            let headR = runResult(git, ["-C", repo, "symbolic-ref", "--quiet", "--short",
                                        "refs/remotes/origin/HEAD"])
            if headR.ok {
                let ref = headR.out.trimmingCharacters(in: .whitespacesAndNewlines) // "origin/main"
                if let slash = ref.lastIndex(of: "/") { base = String(ref[ref.index(after: slash)...]) }
            }
            var ins = 0, del = 0
            // Committed diff of the branch vs its merge-base with the default branch.
            if branch != base {
                let (ok, out) = runResult(git, ["-C", repo, "diff", "--shortstat", "\(base)...HEAD"])
                if ok { (ins, del) = parseShortstat(out) }
            }
            // Plus uncommitted working-tree changes, so it reflects live work.
            let wt = runResult(git, ["-C", repo, "diff", "--shortstat"])
            if wt.ok { let (i, d) = parseShortstat(wt.out); ins += i; del += d }
            return BranchStat(branch: branch, base: base, insertions: ins, deletions: del)
        }.value
    }

    /// Parse `git diff --shortstat` ("… 42 insertions(+), 9 deletions(-)").
    private static func parseShortstat(_ s: String) -> (Int, Int) {
        func num(_ keyword: String) -> Int {
            guard let r = s.range(of: "([0-9]+) \(keyword)", options: .regularExpression) else { return 0 }
            return Int(s[r].prefix(while: { $0.isNumber })) ?? 0
        }
        return (num("insertion"), num("deletion"))
    }

    /// A NON-destructive snapshot of the current working tree: `git stash create`
    /// makes a dangling commit of all changes WITHOUT touching HEAD, the index or
    /// the working tree. Returns its SHA, or nil if the tree is clean / it failed.
    /// Used by loop checkpoints so a run can be rewound to any iteration.
    nonisolated static func snapshot(repo: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return nil }
            let r = runResult(git, ["-C", repo, "stash", "create"])
            let sha = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.ok && !sha.isEmpty ? sha : nil
        }.value
    }

    /// Restore tracked files to a snapshot SHA (`git checkout <sha> -- .`). Safe on
    /// history (only overwrites working-tree files; never deletes or rewrites refs).
    nonisolated static func restore(repo: String, sha: String) async -> Bool {
        await runGit(repo, ["checkout", sha, "--", "."])
    }

    /// Discard an agent's changes to one file (git checkout -- file).
    nonisolated static func revert(repo: String, file: String) async -> Bool {
        await runGit(repo, ["checkout", "--", file])
    }
    /// Stage a file (git add file).
    nonisolated static func stage(repo: String, file: String) async -> Bool {
        await runGit(repo, ["add", "--", file])
    }
    /// Unstage a file (git restore --staged file).
    nonisolated static func unstage(repo: String, file: String) async -> Bool {
        await runGit(repo, ["restore", "--staged", "--", file])
    }
    /// The set of currently-staged files, as ABSOLUTE paths (to match editedFiles).
    nonisolated static func stagedFiles(repo: String) async -> Set<String> {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return [] }
            // NUL-separated + quotePath off so non-ASCII / spaced paths stay intact (they
            // key stage/unstage, so a mangled path would silently no-op).
            let r = runResult(git, ["-C", repo, "-c", "core.quotePath=false",
                                    "diff", "--cached", "--name-only", "-z"])
            guard r.ok else { return [] }
            return Set(r.out.split(separator: "\0", omittingEmptySubsequences: true)
                .map { (repo as NSString).appendingPathComponent(String($0)) })
        }.value
    }
    /// Apply a single-hunk patch (reconstructed by `DiffHunk.unifiedPatch`) to the working
    /// tree via `git apply`, piping the patch on stdin. `reverse` discards the hunk (revert);
    /// otherwise it's applied (used here to stage a single hunk with `--cached`). Returns
    /// (ok, output) so the UI can surface git's own error if the context no longer matches.
    nonisolated static func applyHunkPatch(repo: String, patch: String,
                                           reverse: Bool, cached: Bool) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            var args = ["-C", repo, "apply", "-p1"]
            if cached { args.append("--cached") }
            if reverse { args.append("--reverse") }
            args.append("-")   // read the patch from stdin
            return runWithStdin(git, args, stdin: patch)
        }.value
    }

    /// Run git with data piped to stdin (git apply reads the patch there). Kept separate from
    /// `runStatus`, which nulls stdin to avoid credential-prompt hangs.
    private static func runWithStdin(_ path: String, _ args: [String], stdin: String) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let input = Pipe(); p.standardInput = input
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_ASKPASS"] = "/usr/bin/true"; env["GCM_INTERACTIVE"] = "never"
        p.environment = env
        do { try p.run() } catch { return (false, "git \(args.joined(separator: " ")) failed") }
        LiveProcesses.register(p)
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try? input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        LiveProcesses.deregister(p)
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    /// Commit only what's already staged (no `add -A`).
    nonisolated static func commitStaged(repo: String, message: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            return runResult(git, ["-C", repo, "commit", "-m", message])
        }.value
    }
    /// Stage everything and commit. Returns combined output (for error surfacing).
    nonisolated static func commit(repo: String, message: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            _ = runResult(git, ["-C", repo, "add", "-A"])
            return runResult(git, ["-C", repo, "commit", "-m", message])
        }.value
    }

    private nonisolated static func runGit(_ repo: String, _ args: [String]) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return false }
            return runResult(git, ["-C", repo] + args).ok
        }.value
    }

    // MARK: - Repo lifecycle (clone / branch / push) — Code section

    /// Whether `git` is available at all (for gating clone/push UI).
    static var isAvailable: Bool { gitPath() != nil }

    /// A local folder name inferred from a clone URL ("git@…/foo.git" → "foo").
    static func repoName(from url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        let last = (s as NSString).lastPathComponent
        return last.isEmpty ? "repo" : last
    }

    /// Clone `url` into `parentDir/<name>` (never clobbering an existing folder).
    /// Returns the local path on success. Relies on the user's own git credentials.
    nonisolated static func clone(url: String, into parentDir: String) async -> (ok: Bool, path: String?, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, nil, "git not found") }
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            let base = (parentDir as NSString).appendingPathComponent(repoName(from: url))
            var dest = base; var n = 2
            while FileManager.default.fileExists(atPath: dest) { dest = "\(base)-\(n)"; n += 1 }
            let r = runResult(git, ["clone", "--", url, dest])
            return (r.ok, r.ok ? dest : nil, r.out)
        }.value
    }

    /// Create a branch off HEAD and switch to it.
    nonisolated static func createBranch(repo: String, name: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            return runResult(git, ["-C", repo, "checkout", "-b", name])
        }.value
    }

    /// List local branches (current first).
    nonisolated static func branches(repo: String) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return [] }
            let r = runResult(git, ["-C", repo, "branch", "--format=%(refname:short)"])
            guard r.ok else { return [] }
            return r.out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }.value
    }

    /// Switch to an existing branch.
    nonisolated static func checkout(repo: String, branch: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            return runResult(git, ["-C", repo, "checkout", branch])
        }.value
    }

    // MARK: - Changed files (list + per-file +/−)

    /// One changed file in the working tree, with its insertions/deletions vs HEAD and
    /// what kind of change it is — for a Claude-style "files changed" list.
    struct ChangedFile: Identifiable, Hashable {
        enum Kind: String { case modified, added, deleted, untracked, renamed }
        var id: String { path }
        let path: String        // repo-relative
        let insertions: Int
        let deletions: Int
        let kind: Kind
    }

    /// Every changed file in `repo` (working tree + index vs HEAD, plus untracked), each
    /// with +insertions / −deletions and a change kind. `git diff HEAD --numstat` gives
    /// the counts for tracked files; `status --porcelain` supplies the kind and untracked
    /// files (whose lines we count directly, since they're not in the diff yet).
    nonisolated static func changedFiles(repo: String) async -> [ChangedFile] {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return [] }
            // `-c core.quotePath=false` keeps non-ASCII paths intact (no octal escaping);
            // `-z` NUL-separates records so spaces/newlines in paths don't split a row —
            // otherwise stage/revert would operate on mangled, non-existent paths.
            let numstat = runResult(git, ["-C", repo, "-c", "core.quotePath=false",
                                          "diff", "HEAD", "--numstat"])
            let status = runResult(git, ["-C", repo, "-c", "core.quotePath=false",
                                         "status", "--porcelain", "-z"])
            guard status.ok else { return [] }
            var files = parseChangedFiles(numstat: numstat.ok ? numstat.out : "", statusZ: status.out)
            // Fill untracked new-file line counts (they're not in `diff HEAD`).
            files = files.map { f in
                guard f.kind == .untracked, f.insertions == 0, f.deletions == 0 else { return f }
                let full = (repo as NSString).appendingPathComponent(f.path)
                guard let content = try? String(contentsOfFile: full, encoding: .utf8), !content.isEmpty
                else { return f }
                let lines = content.split(separator: "\n", omittingEmptySubsequences: false).count
                return ChangedFile(path: f.path, insertions: lines, deletions: 0, kind: .untracked)
            }
            return files.sorted { $0.path < $1.path }
        }.value
    }

    /// Pure parser for `git diff HEAD --numstat` + `git status --porcelain -z`, so path
    /// edge cases (spaces, non-ASCII, renames, binaries) are unit-testable without a repo.
    /// Untracked files come back with 0/0 (the caller fills their line counts).
    static func parseChangedFiles(numstat: String, statusZ: String) -> [ChangedFile] {
        var stats: [String: (add: Int, del: Int)] = [:]
        for line in numstat.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard p.count == 3 else { continue }
            // Binary files show "-" for the counts → treat as 0.
            stats[p[2]] = (Int(p[0]) ?? 0, Int(p[1]) ?? 0)
        }
        // NUL-separated records; a rename/copy is TWO records (new path, then old path).
        let fields = statusZ.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var files: [ChangedFile] = []
        var i = 0
        while i < fields.count {
            let entry = fields[i]; i += 1
            guard entry.count > 3 else { continue }
            let xy = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            if xy.contains("R") || xy.contains("C"), i < fields.count { i += 1 }   // consume the old path
            let kind: ChangedFile.Kind
            if xy == "??" { kind = .untracked }
            else if xy.contains("R") { kind = .renamed }
            else if xy.contains("D") { kind = .deleted }
            else if xy.contains("A") { kind = .added }
            else { kind = .modified }
            let (add, del) = stats[path] ?? (0, 0)
            files.append(ChangedFile(path: path, insertions: add, deletions: del, kind: kind))
        }
        return files
    }

    // MARK: - Worktree isolation (loops)

    /// Add a git worktree at `path` on a new `branch` off the repo's HEAD. Used to run
    /// a loop in its own tree so parallel loops never fight over the working copy.
    nonisolated static func addWorktree(repo: String, path: String, branch: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            return runResult(git, ["-C", repo, "worktree", "add", "-b", branch, path, "HEAD"])
        }.value
    }

    /// Stage everything and commit in `dir` (typically a worktree). ok == false when
    /// there was nothing to commit — the caller treats that as "no work produced".
    nonisolated static func commitAll(dir: String, message: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            _ = runResult(git, ["-C", dir, "add", "-A"])
            return runResult(git, ["-C", dir, "commit", "-m", message])
        }.value
    }

    /// Merge `branch` into whatever `repo` has checked out (its base branch), no-ff so
    /// the loop's work stays a reviewable unit. On conflict git leaves a merge in
    /// progress — the caller aborts (`abortMerge`) and leaves the branch for review.
    nonisolated static func mergeNoFF(repo: String, branch: String, message: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            return runResult(git, ["-C", repo, "merge", "--no-ff", branch, "-m", message])
        }.value
    }

    /// Abort an in-progress merge (after a conflict), restoring the base branch.
    nonisolated static func abortMerge(repo: String) async {
        _ = await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return }
            _ = runResult(git, ["-C", repo, "merge", "--abort"])
        }.value
    }

    /// Remove a worktree (force, since it may hold committed-but-unmerged work we
    /// intentionally keep on its branch).
    nonisolated static func removeWorktree(repo: String, path: String) async {
        _ = await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return }
            _ = runResult(git, ["-C", repo, "worktree", "remove", path, "--force"])
        }.value
    }

    /// Delete a local branch (used to clean up after a successful merge).
    nonisolated static func deleteBranch(repo: String, name: String) async {
        _ = await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return }
            _ = runResult(git, ["-C", repo, "branch", "-D", name])
        }.value
    }

    /// Push the current branch to origin, setting upstream. Returns combined output.
    nonisolated static func push(repo: String) async -> (ok: Bool, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return (false, "git not found") }
            let branch = runResult(git, ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"])
                .out.trimmingCharacters(in: .whitespacesAndNewlines)
            return runResult(git, ["-C", repo, "push", "-u", "origin", branch])
        }.value
    }

    /// True if the working tree has uncommitted changes.
    nonisolated static func hasUncommittedChanges(repo: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let git = gitPath() else { return false }
            return !runResult(git, ["-C", repo, "status", "--porcelain"])
                .out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.value
    }

    /// Parse a unified diff into displayable lines with old/new line numbers.
    static func parse(_ diff: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldNum = 0, newNum = 0
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if raw.hasPrefix("diff --git") || raw.hasPrefix("index ")
                || raw.hasPrefix("--- ") || raw.hasPrefix("+++ ")
                || raw.hasPrefix("new file") || raw.hasPrefix("deleted file")
                || raw.hasPrefix("similarity") || raw.hasPrefix("rename ") {
                continue
            }
            if raw.hasPrefix("@@") {
                // @@ -oldStart,oldLen +newStart,newLen @@
                if let nums = hunkStarts(raw) { oldNum = nums.0; newNum = nums.1 }
                lines.append(DiffLine(id: lines.count, kind: .hunk, oldNumber: nil, newNumber: nil, text: raw))
                continue
            }
            if raw.hasPrefix("+") {
                lines.append(DiffLine(id: lines.count, kind: .add, oldNumber: nil, newNumber: newNum, text: String(raw.dropFirst())))
                newNum += 1
            } else if raw.hasPrefix("-") {
                lines.append(DiffLine(id: lines.count, kind: .del, oldNumber: oldNum, newNumber: nil, text: String(raw.dropFirst())))
                oldNum += 1
            } else {
                let t = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                lines.append(DiffLine(id: lines.count, kind: .context, oldNumber: oldNum, newNumber: newNum, text: t))
                oldNum += 1; newNum += 1
            }
        }
        return lines
    }

    private static func hunkStarts(_ header: String) -> (Int, Int)? {
        // e.g. "@@ -12,7 +12,9 @@ func foo()"
        let parts = header.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        func start(_ token: Substring) -> Int? {
            let body = token.dropFirst()                       // drop +/-
            let n = body.split(separator: ",").first ?? body
            return Int(n)
        }
        guard let o = start(parts[1]), let n = start(parts[2]) else { return nil }
        return (o, n)
    }
}
