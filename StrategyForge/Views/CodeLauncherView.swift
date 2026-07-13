//
//  CodeLauncherView.swift
//  StrategyForge
//
//  The repo-first "door" for the Code section: connect a repo (clone a GitHub URL
//  or pick a folder), or resume the last one, and drop straight into a single-agent
//  Claude Code session with the diffs/terminal/git workspace. No team design — as
//  simple as Claude Code: connect a repo and start talking.
//

import SwiftUI

struct CodeLauncherView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("code.lastRepo") private var lastRepo = ""
    @State private var cloneURL = ""
    @State private var cloning = false
    @State private var ghRepos: [GitHubCLI.RepoRef] = []
    @State private var loadingRepos = false
    @State private var repoQuery = ""
    @State private var newRepoName = ""
    @State private var newRepoPrivate = true
    @State private var creatingRepo = false

    private var recentPaths: [String] { model.recentRepoPaths.filter { $0 != lastRepo } }

    /// GitHub repos filtered by the search box; capped when not searching so a big
    /// account doesn't flood the launcher.
    private var filteredRepos: [GitHubCLI.RepoRef] {
        let q = repoQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(ghRepos.prefix(8)) }
        return ghRepos.filter {
            $0.nameWithOwner.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                if !lastRepo.isEmpty, FileManager.default.fileExists(atPath: lastRepo) { resumeCard }
                if !recentPaths.isEmpty { recentCard }
                // Your GitHub repos, listed to pick from (like Claude Code) — clones on
                // choose. Falls back to the manual URL field below if gh isn't signed in.
                if loadingRepos || !ghRepos.isEmpty { githubReposCard }
                // Start something brand-new on GitHub without leaving the app.
                createRepoCard
                // Open a LOCAL folder — the Claude-Code habit (work on a checkout you
                // already have, nothing is cloned).
                pickCard
                cloneCard
                credentialsNote
                if !CodeGit.isAvailable { gitMissingNote }
            }
            .frame(maxWidth: 640)
            .padding(Space.xl)
            .frame(maxWidth: .infinity)   // center the column
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .task { await loadRepos() }
    }

    // MARK: Recent repos

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("clock.arrow.circlepath", model.t("code.recent.title"),
                          subtitle: model.t("code.recent.subtitle"))
            ForEach(recentPaths, id: \.self) { path in
                Button { model.openCodeChat(repoURL: URL(fileURLWithPath: path)) } label: {
                    repoRow(icon: "folder.fill",
                            title: (path as NSString).lastPathComponent,
                            subtitle: prettyPath(path), badge: nil)
                }
                .buttonStyle(.plain).hoverLift()
            }
        }
        .card()
    }

    // MARK: My GitHub repos

    private var githubReposCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("cloud", model.t("code.myRepos.title"), subtitle: model.t("code.myRepos.subtitle"))
            if loadingRepos {
                HStack(spacing: Space.s) {
                    WorkingLogo(size: 16); Text(model.t("code.myRepos.loading")).font(.sfCaption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.xs)
            } else {
                // Search so a large account isn't an endless scroll (only shown when
                // there's enough to warrant it).
                if ghRepos.count > 8 {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField(model.t("code.myRepos.search"), text: $repoQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.insetBg))
                }
                ForEach(filteredRepos) { repo in
                    Button {
                        cloning = true
                        Task { await model.cloneAndOpenCodeChat(url: repo.url); cloning = false }
                    } label: {
                        repoRow(icon: repo.isPrivate ? "lock.fill" : "globe",
                                title: repo.nameWithOwner,
                                subtitle: repo.description.isEmpty ? nil : repo.description,
                                badge: repo.isPrivate ? model.t("code.myRepos.private") : nil)
                    }
                    .buttonStyle(.plain).hoverLift()
                    .disabled(cloning)
                }
                if repoQuery.trimmingCharacters(in: .whitespaces).isEmpty, ghRepos.count > filteredRepos.count {
                    Text(model.t("code.myRepos.more", ghRepos.count - filteredRepos.count))
                        .font(.sfCaption2).foregroundStyle(.tertiary).padding(.leading, Space.s)
                }
            }
        }
        .card()
    }

    /// Create a brand-new GitHub repo and open it — no trip to github.com.
    private var createRepoCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader("plus.rectangle.on.folder", model.t("code.newRepo.title"),
                          subtitle: model.t("code.newRepo.subtitle"))
            HStack(spacing: Space.s) {
                TextField(model.t("code.newRepo.name"), text: $newRepoName)
                    .textFieldStyle(.roundedBorder).font(.sfCode).disabled(creatingRepo)
                    .onSubmit(createRepo)
                Toggle(isOn: $newRepoPrivate) { Text(model.t("code.newRepo.private")) }
                    .toggleStyle(.checkbox).fixedSize()
                Button(action: createRepo) {
                    if creatingRepo {
                        HStack(spacing: Space.s) { WorkingLogo(size: 15, color: Theme.onAccent); Text(model.t("code.newRepo.creating")) }
                    } else {
                        Label(model.t("code.newRepo.action"), systemImage: "plus")
                    }
                }
                .buttonStyle(.moon)
                .disabled(creatingRepo || newRepoName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .card()
    }

    private func createRepo() {
        let name = newRepoName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !creatingRepo else { return }
        creatingRepo = true
        Task {
            await model.createAndOpenGitHubRepo(name: name, isPrivate: newRepoPrivate)
            newRepoName = ""
            creatingRepo = false
        }
    }

    /// One tappable repo row (recent or GitHub): icon + name + subtitle + chevron.
    private func repoRow(icon: String, title: String, subtitle: String?, badge: String?) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.sfCallout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.s)
            if let badge {
                Text(badge).font(.sfCaption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.insetBg))
            }
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func prettyPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func loadRepos() async {
        guard ghRepos.isEmpty, !loadingRepos else { return }
        loadingRepos = true
        ghRepos = await GitHubCLI.listRepos()
        loadingRepos = false
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconBadge(systemName: "chevron.left.forwardslash.chevron.right")
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t("code.launcher.title")).font(.sfDisplay)
                Text(model.t("code.launcher.subtitle"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Clone from GitHub

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("arrow.down.circle", model.t("code.clone.title"),
                          subtitle: model.t("code.clone.subtitle"))
            HStack(spacing: Space.s) {
                TextField("https://github.com/owner/repo", text: $cloneURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.sfCode)
                    .disabled(cloning)
                    .onSubmit(clone)
                Button(action: clone) {
                    if cloning {
                        HStack(spacing: Space.s) { WorkingLogo(size: 15, color: Theme.onAccent); Text(model.t("code.cloning")) }
                    } else {
                        Label(model.t("code.clone.action"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.moon)
                .disabled(cloning || cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .card()
    }

    private func clone() {
        let url = cloneURL
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !cloning else { return }
        cloning = true
        Task {
            await model.cloneAndOpenCodeChat(url: url)
            cloning = false
        }
    }

    // MARK: Pick a folder

    private var pickCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("folder", model.t("code.pick.title"),
                          subtitle: model.t("code.pick.subtitle")) {
                Button(model.t("code.pick.action")) { model.pickAndOpenCodeChat() }
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    // MARK: Resume last

    private var resumeCard: some View {
        Button {
            model.openCodeChat(repoURL: URL(fileURLWithPath: lastRepo))
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("code.resume.title")).font(.sfCardTitle)
                    Text((lastRepo as NSString).lastPathComponent).font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
    }

    /// Clarify that there's no in-app GitHub login — it uses the user's own creds.
    private var credentialsNote: some View {
        Label(model.t("code.credsNote"), systemImage: "info.circle")
            .font(.sfCaption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var gitMissingNote: some View {
        Label(model.t("code.gitMissing"), systemImage: "exclamationmark.triangle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}
