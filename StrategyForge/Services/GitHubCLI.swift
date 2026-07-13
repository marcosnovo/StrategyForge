//
//  GitHubCLI.swift
//  StrategyForge
//
//  A tiny wrapper around GitHub's `gh` CLI so Code mode can open a pull request in
//  one tap — using the user's OWN gh/git credentials (no app tokens), the same
//  "bring your own login" bet the rest of the app makes. Everything runs as a
//  subprocess off the main thread; every call degrades gracefully when `gh` is
//  missing or not authenticated so the UI can guide the user instead of failing.
//

import Foundation

enum GitHubCLI {

    /// The `gh` executable, if installed.
    private static func ghPath() -> String? {
        let fm = FileManager.default
        for p in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where fm.isExecutableFile(atPath: p) {
            return p
        }
        return ClaudeRunner.resolveBinary("gh")
    }

    /// Whether the GitHub CLI is installed at all (gate the PR button).
    static var isInstalled: Bool { ghPath() != nil }

    /// Whether `gh auth status` succeeds (the user is logged in to GitHub).
    nonisolated static func isAuthenticated() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return false }
            return run(gh, ["auth", "status"], cwd: nil).ok
        }.value
    }

    /// Open a pull request from the current branch of `repo`. Returns the PR URL on
    /// success (gh prints it to stdout). `gh` resolves the base branch + remote itself.
    nonisolated static func createPR(repo: String, title: String, body: String) async -> (ok: Bool, url: String?, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return (false, nil, "GitHub CLI (gh) not found") }
            let r = run(gh, ["pr", "create", "--title", title, "--body", body], cwd: repo)
            // gh prints the PR URL on success; surface it for a "View PR" affordance.
            let url = r.out.split(whereSeparator: \.isNewline)
                .map(String.init).last(where: { $0.hasPrefix("https://") })
            return (r.ok, url, r.out)
        }.value
    }

    /// A pull request's headline status for the working branch.
    struct PRInfo: Sendable, Equatable {
        var number: Int
        var state: String   // OPEN · MERGED · CLOSED
        var url: String
        var title: String
        var isDraft: Bool
    }

    /// The PR (if any) for `branch`, with its state — for the composer branch bar.
    /// Returns nil when gh is missing, unauthenticated, or no PR exists.
    nonisolated static func prInfo(repo: String, branch: String) async -> PRInfo? {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return nil }
            let r = run(gh, ["pr", "view", branch, "--json", "number,state,url,title,isDraft"], cwd: repo)
            guard r.ok, let data = r.out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let number = obj["number"] as? Int else { return nil }
            return PRInfo(number: number,
                          state: (obj["state"] as? String) ?? "OPEN",
                          url: (obj["url"] as? String) ?? "",
                          title: (obj["title"] as? String) ?? "",
                          isDraft: (obj["isDraft"] as? Bool) ?? false)
        }.value
    }

    /// A GitHub repository the signed-in user can open (for the Code launcher list).
    struct RepoRef: Sendable, Hashable, Identifiable {
        var nameWithOwner: String
        var description: String
        var isPrivate: Bool
        var url: String
        var id: String { nameWithOwner }
        var name: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
    }

    /// The signed-in user's repositories (newest first), via `gh repo list`. Empty
    /// when gh is missing/unauthenticated — the caller shows the manual clone field.
    nonisolated static func listRepos(limit: Int = 50) async -> [RepoRef] {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return [] }
            let r = run(gh, ["repo", "list", "--limit", "\(limit)",
                             "--json", "nameWithOwner,description,isPrivate,url"], cwd: nil)
            guard r.ok, let data = r.out.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { d -> RepoRef? in
                guard let nwo = d["nameWithOwner"] as? String, !nwo.isEmpty else { return nil }
                return RepoRef(nameWithOwner: nwo,
                               description: (d["description"] as? String) ?? "",
                               isPrivate: (d["isPrivate"] as? Bool) ?? false,
                               url: (d["url"] as? String) ?? "https://github.com/\(nwo)")
            }
        }.value
    }

    /// Create a NEW repo on GitHub under the signed-in account and clone it into
    /// `parentDir/<name>` — so you never have to leave for github.com to start one.
    nonisolated static func createRepo(name: String, isPrivate: Bool,
                                       into parentDir: String) async -> (ok: Bool, path: String?, out: String) {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return (false, nil, "GitHub CLI (gh) not found") }
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            let r = run(gh, ["repo", "create", name, isPrivate ? "--private" : "--public",
                             "--clone", "--add-readme"], cwd: parentDir)
            let path = (parentDir as NSString).appendingPathComponent(name)
            let ok = r.ok && FileManager.default.fileExists(atPath: path)
            return (ok, ok ? path : nil, r.out)
        }.value
    }

    /// A skill discovered across public GitHub repos (community catalog).
    struct RemoteSkill: Sendable, Hashable, Identifiable {
        var owner: String, repo: String, path: String, slug: String
        var stars: Int, pushedAt: String, defaultBranch: String
        var id: String { "\(owner)/\(repo)/\(path)" }
    }

    /// Discover skills across public repos by CODE-searching for `SKILL.md` files
    /// (needs auth — `gh` provides it), then ranking by the source repo's stars.
    /// Code search naturally excludes "awesome-list" repos (they have no SKILL.md).
    /// Returns [] when gh is missing/unauthenticated so the caller can fall back.
    nonisolated static func searchCommunitySkills(limit: Int = 60) async -> [RemoteSkill] {
        await Task.detached(priority: .userInitiated) {
            guard let gh = ghPath() else { return [] }
            let r = run(gh, ["api", "-X", "GET", "search/code",
                             "-f", "q=filename:SKILL.md", "-F", "per_page=100"], cwd: nil)
            guard r.ok, let data = r.out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["items"] as? [[String: Any]] else { return [] }
            struct Hit { let owner: String, repo: String, path: String, slug: String }
            var hits: [Hit] = []; var seen = Set<String>()
            for it in items {
                guard let path = it["path"] as? String, path.lowercased().hasSuffix("skill.md"),
                      let repoObj = it["repository"] as? [String: Any],
                      let full = repoObj["full_name"] as? String else { continue }
                let parts = full.split(separator: "/"); guard parts.count == 2 else { continue }
                let dir = (path as NSString).deletingLastPathComponent
                // Skip the repo-root SKILL.md (spec/template), keep real skill folders.
                guard !dir.isEmpty else { continue }
                let slug = dir.split(separator: "/").last.map(String.init) ?? String(parts[1])
                let key = "\(full)/\(dir)"
                if seen.contains(key) { continue }; seen.insert(key)
                hits.append(Hit(owner: String(parts[0]), repo: String(parts[1]), path: dir, slug: slug))
            }
            // Fetch stars + default branch per unique repo. Bounded to ~30 (each is a
            // subprocess round-trip) to keep the one-time load snappy; repos beyond
            // that are dropped rather than shown without a rank.
            var meta: [String: (Int, String, String)] = [:]
            // Preserve first-seen (search-relevance) order for the repo cap.
            var repoOrder: [String] = []
            for h in hits { let f = "\(h.owner)/\(h.repo)"; if !repoOrder.contains(f) { repoOrder.append(f) } }
            for full in repoOrder.prefix(30) {
                let rr = run(gh, ["api", "repos/\(full)"], cwd: nil)
                if rr.ok, let d = rr.out.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    meta[full] = ((o["stargazers_count"] as? Int) ?? 0,
                                  (o["pushed_at"] as? String) ?? "",
                                  (o["default_branch"] as? String) ?? "main")
                }
            }
            let out = hits.compactMap { h -> RemoteSkill? in
                guard let m = meta["\(h.owner)/\(h.repo)"] else { return nil }
                return RemoteSkill(owner: h.owner, repo: h.repo, path: h.path, slug: h.slug,
                                   stars: m.0, pushedAt: m.1, defaultBranch: m.2)
            }.sorted { $0.stars > $1.stars }
            return Array(out.prefix(limit))
        }.value
    }

    /// Run a subprocess in `cwd`, returning success + combined output.
    private static func run(_ path: String, _ args: [String], cwd: String?) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        do { try p.run() } catch { return (false, "gh \(args.joined(separator: " ")) failed to launch") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
