//
//  CodeModeView.swift
//  StrategyForge
//
//  A developer workspace shown in place of the chat transcript when Code Mode is
//  on: the files the agent changed on the left (with per-file +/− and change kind),
//  the selected file's contents or diff on the right, plus git actions — branch bar,
//  one-tap Commit + PR and opt-in Auto-PR when a run finishes.
//

import SwiftUI

struct CodeModeView: View {
    @Environment(AppModel.self) private var model
    var vm: ChatViewModel
    @State private var selected: String?
    @State private var diffLines: [DiffLine]?
    /// Raw file text for the non-diff view, loaded off the main thread (never read
    /// synchronously in `body`).
    @State private var fileText = ""
    @State private var loadingDiff = false
    @State private var viewMode: ViewMode = .diff
    enum ViewMode: String, CaseIterable { case diff, file }

    // Git panel state
    @State private var branch: String?
    @State private var confirmRevert: String?
    @State private var commitMessage = ""
    @State private var confirmCommit = false
    @State private var gitBusy = false
    @State private var gitError: String?
    @State private var showTerminal = true
    // Push & PR
    @State private var pushing = false
    @State private var prURL: String?
    /// When on, a finished run auto-commits its changes, pushes, and opens (or updates)
    /// a PR — the "ship it while I sleep" flow. Off by default; per-app.
    @AppStorage("code.autoPR") private var autoPR = false
    /// The pull request for the current branch (open/merged/closed), if any — so Code
    /// Mode shows the generated PR, its state, links to its diff, and a merge button.
    @State private var pr: GitHubCLI.PRInfo?
    @State private var merging = false
    // Branch switching
    @State private var branches: [String] = []
    @State private var showNewBranch = false
    @State private var newBranchName = ""
    // Per-file staging (absolute paths, matching editedFiles)
    @State private var staged: Set<String> = []
    /// Per-file +insertions / −deletions + change kind, keyed by repo-relative path.
    @State private var changeStats: [String: CodeGit.ChangedFile] = [:]

    private var isRepo: Bool { !(vm.config.repoPath ?? "").isEmpty }

    private var files: [String] { vm.editedFiles }

    var body: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: 240)
            Divider()
            fileViewer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selected == nil { selected = files.first }
            Task { await loadDiff() }
            Task { await loadStaged() }
            Task { await loadChangeStats() }
            Task {
                if let repo = vm.config.repoPath {
                    branch = await CodeGit.currentBranch(repo: repo)
                    branches = await CodeGit.branches(repo: repo)
                    await refreshPR()
                }
            }
        }
        .onChange(of: vm.editedFiles) { _, new in
            if selected == nil || !(new.contains(selected ?? "")) { selected = new.first }
            Task { await loadChangeStats() }
        }
        // Refresh the +/− once a run settles (the agent finished editing), and — when
        // Auto-PR is on — commit, push and open/update the PR automatically.
        .onChange(of: vm.isRunning) { _, running in
            if !running {
                Task {
                    await loadChangeStats()
                    if autoPR, isRepo, GitHubCLI.isInstalled, !changeStats.isEmpty {
                        commitAndPR(auto: true)
                    }
                }
            }
        }
        .onChange(of: selected) { Task { await loadDiff() } }
        .confirmationDialog(model.t("code.revertConfirm"), isPresented: revertBinding, titleVisibility: .visible) {
            Button(model.t("code.revert"), role: .destructive) { performRevert() }
            Button(model.t("common.cancel"), role: .cancel) { confirmRevert = nil }
        }
        .confirmationDialog(model.t("code.commitConfirm"), isPresented: $confirmCommit, titleVisibility: .visible) {
            Button(model.t("code.commit")) { performCommit() }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
        .alert(model.t("code.branch.new"), isPresented: $showNewBranch) {
            TextField(model.t("code.branch.placeholder"), text: $newBranchName)
            Button(model.t("common.cancel"), role: .cancel) {}
            Button(model.t("code.branch.create")) { createNewBranch() }
        }
    }

    private var revertBinding: Binding<Bool> {
        Binding(get: { confirmRevert != nil }, set: { if !$0 { confirmRevert = nil } })
    }

    private func performRevert() {
        guard let file = confirmRevert, let repo = vm.config.repoPath else { return }
        confirmRevert = nil; gitBusy = true
        Task {
            _ = await CodeGit.revert(repo: repo, file: file)
            await loadDiff(); gitBusy = false
        }
    }
    private func performStage() {
        guard let file = selected, let repo = vm.config.repoPath else { return }
        gitBusy = true
        Task {
            _ = await CodeGit.stage(repo: repo, file: file)
            staged = await CodeGit.stagedFiles(repo: repo)
            gitBusy = false
        }
    }
    private func performCommit() {
        guard let repo = vm.config.repoPath, !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        gitBusy = true; gitError = nil
        Task {
            // If the user staged specific files, commit only those; otherwise commit
            // everything (the default one-shot flow).
            let r = staged.isEmpty ? await CodeGit.commit(repo: repo, message: commitMessage)
                                   : await CodeGit.commitStaged(repo: repo, message: commitMessage)
            if r.ok { commitMessage = ""; await loadDiff() } else { gitError = r.out }
            staged = await CodeGit.stagedFiles(repo: repo)
            branch = await CodeGit.currentBranch(repo: repo)
            gitBusy = false
        }
    }

    private func loadDiff() async {
        guard let path = selected, let repo = vm.config.repoPath, !repo.isEmpty else {
            diffLines = nil; fileText = ""; return
        }
        loadingDiff = true
        diffLines = await CodeGit.diff(repo: repo, file: path)
        // Load the raw file off-main for the non-diff view.
        let unreadable = model.t("code.unreadable")
        fileText = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? unreadable
        }.value
        loadingDiff = false
    }

    // MARK: Left — changed files

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.t("code.changed")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                    Spacer()
                    if !files.isEmpty {
                        Text("\(files.count)").font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                if isRepo { branchMenu }
            }
            .padding(Space.m)
            Divider()
            if files.isEmpty {
                emptyFiles
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files, id: \.self) { path in fileRow(path) }
                    }
                    .padding(Space.s)
                }
            }
        }
        .background(Theme.insetBg)
    }

    private func fileRow(_ path: String) -> some View {
        let isSel = selected == path
        let isStaged = staged.contains(path)
        return HStack(spacing: 4) {
            // Checkbox: stage / unstage this file for a selective commit.
            if isRepo {
                Button { toggleStage(path) } label: {
                    Image(systemName: isStaged ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isStaged ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .help(model.t(isStaged ? "code.unstage" : "code.stage"))
            }
            Button { selected = path } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: icon(for: path)).font(.system(size: 11))
                        .foregroundStyle(isSel ? Theme.accent : .secondary).frame(width: 16)
                    Text((path as NSString).lastPathComponent)
                        .font(.sfCaption2.weight(isSel ? .semibold : .regular))
                        .foregroundStyle(isSel ? .primary : .secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    // Per-file change size + kind — the "how much did each change" signal.
                    if let s = stat(for: path) {
                        changeBadge(s)
                    }
                }
                .padding(.horizontal, Space.s).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(isSel ? Theme.accentSoft : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A compact "+12 −3" with an M/A/D/U kind letter, so each file shows how much it
    /// changed at a glance (Claude-style).
    @ViewBuilder
    private func changeBadge(_ s: CodeGit.ChangedFile) -> some View {
        HStack(spacing: 4) {
            if s.insertions > 0 {
                Text("+\(s.insertions)").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.success)
            }
            if s.deletions > 0 {
                Text("−\(s.deletions)").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.danger)
            }
            Text(kindLetter(s.kind))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(kindColor(s.kind))
                .frame(width: 12, height: 12)
                .background(RoundedRectangle(cornerRadius: 3).fill(kindColor(s.kind).opacity(0.15)))
        }
    }

    private func kindLetter(_ k: CodeGit.ChangedFile.Kind) -> String {
        switch k {
        case .modified: return "M"
        case .added, .untracked: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        }
    }
    private func kindColor(_ k: CodeGit.ChangedFile.Kind) -> Color {
        switch k {
        case .modified, .renamed: return Theme.accent
        case .added, .untracked: return Theme.success
        case .deleted: return Theme.danger
        }
    }

    private func toggleStage(_ path: String) {
        guard let repo = vm.config.repoPath else { return }
        Task {
            if staged.contains(path) { _ = await CodeGit.unstage(repo: repo, file: path) }
            else { _ = await CodeGit.stage(repo: repo, file: path) }
            staged = await CodeGit.stagedFiles(repo: repo)
        }
    }

    private func loadStaged() async {
        guard let repo = vm.config.repoPath else { staged = []; return }
        staged = await CodeGit.stagedFiles(repo: repo)
    }

    private func loadChangeStats() async {
        guard let repo = vm.config.repoPath else { changeStats = [:]; return }
        let files = await CodeGit.changedFiles(repo: repo)
        changeStats = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The git +/− stats for an absolute file path (matches on the repo-relative tail,
    /// falling back to the filename so agent-reported paths still line up).
    private func stat(for absPath: String) -> CodeGit.ChangedFile? {
        if let repo = vm.config.repoPath, absPath.hasPrefix(repo) {
            let rel = String(absPath.dropFirst(repo.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let hit = changeStats[rel] { return hit }
        }
        let name = (absPath as NSString).lastPathComponent
        return changeStats.values.first { ($0.path as NSString).lastPathComponent == name }
    }

    private var emptyFiles: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(.tertiary)
            Text(model.t("code.noChanges")).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.l)
    }

    // MARK: Right — file viewer

    private var fileViewer: some View {
        Group {
            if let path = selected {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        Image(systemName: icon(for: path)).foregroundStyle(Theme.accent)
                        Text((path as NSString).lastPathComponent).font(.sfCallout.weight(.semibold))
                        if loadingDiff { WorkingLogo(size: 16) }
                        Spacer()
                        // Diff / File switch (Diff only offered when we have one).
                        if diffLines != nil {
                            Picker("", selection: $viewMode) {
                                Text(model.t("code.diff")).tag(ViewMode.diff)
                                Text(model.t("code.file")).tag(ViewMode.file)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(model.t("chat.reveal"))
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(model.t("filepreview.open"))
                        // Accept (stage) / Revert (discard) the agent's changes.
                        if isRepo, diffLines != nil {
                            Button(model.t("code.accept")) { performStage() }
                                .controlSize(.small).disabled(gitBusy)
                            Button(model.t("code.revert"), role: .destructive) { confirmRevert = path }
                                .controlSize(.small).disabled(gitBusy)
                        }
                    }
                    .padding(Space.m)
                    Divider()
                    if let diff = diffLines, viewMode == .diff {
                        DiffScrollView(lines: diff)
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            Text(fileText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Space.m)
                        }
                    }
                    if !vm.commandLog.isEmpty { terminalPane }
                    if isRepo { prStatusBar }
                    if isRepo { commitBar }
                }
            } else {
                VStack(spacing: Space.s) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text(model.t("code.pick")).font(.sfCallout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.appBg)
    }

    /// Collapsible terminal: the shell commands the agent ran + their output.
    private var terminalPane: some View {
        VStack(spacing: 0) {
            Divider()
            Button { withAnimation(.easeInOut(duration: 0.15)) { showTerminal.toggle() } } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "terminal").font(.system(size: 11))
                    Text(model.t("code.terminal")).font(.sfFieldLabel).tracking(0.8)
                    Text("\(vm.commandLog.count)").font(.sfCaption2).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showTerminal ? "chevron.down" : "chevron.up").font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showTerminal {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(vm.commandLog) { run in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("$").foregroundStyle(Theme.accent)
                                    Text(run.command).foregroundStyle(.primary)
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                if !run.output.isEmpty {
                                    Text(run.output.count > 4000 ? String(run.output.suffix(4000)) : run.output)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
                .background(Theme.insetBg)
            }
        }
    }

    /// Commit staged/working changes with an editable, auto-drafted message.
    private var commitBar: some View {
        VStack(spacing: 0) {
            Divider()
            if let gitError {
                Label(gitError, systemImage: "exclamationmark.triangle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.danger)
                    .padding(.horizontal, Space.m).padding(.top, Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Space.s) {
                TextField(model.t("code.commitPlaceholder"), text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty { confirmCommit = true } }
                if gitBusy || pushing { WorkingLogo(size: 16) }
                Button(model.t("code.commit")) { confirmCommit = true }
                    .buttonStyle(.bordered)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || gitBusy || pushing)
                // One tap: commit everything, push, and open/update the PR (needs gh).
                if GitHubCLI.isInstalled {
                    Button { commitAndPR() } label: {
                        Label(model.t("code.commitPR"), systemImage: "arrow.up.right.circle.fill")
                    }
                    .buttonStyle(.moon)
                    .disabled(gitBusy || pushing)
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            // Auto-PR: ship a finished run automatically (commit → push → PR).
            if GitHubCLI.isInstalled {
                Toggle(isOn: $autoPR) {
                    Text(model.t("code.autoPR")).font(.sfCaption2)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .padding(.horizontal, Space.m).padding(.bottom, Space.xs)
                .help(model.t("code.autoPR.help"))
            }
            if let prURL {
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.success)
                    Link(model.t("code.viewPR"), destination: URL(string: prURL) ?? URL(fileURLWithPath: "/"))
                        .font(.sfCaption2)
                }
                .padding(.horizontal, Space.m).padding(.bottom, Space.s)
            } else if !GitHubCLI.isInstalled {
                Text(model.t("code.ghMissing")).font(.sfCaption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, Space.m).padding(.bottom, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(.bar)
        .onAppear { if commitMessage.isEmpty { commitMessage = draftMessage() } }
    }

    // MARK: Branch switcher

    /// A dropdown to switch branches or create a new one (git blocks a switch with a
    /// dirty tree, so this can't silently lose work).
    private var branchMenu: some View {
        Menu {
            ForEach(branches, id: \.self) { b in
                Button { switchBranch(b) } label: {
                    Label(b, systemImage: b == branch ? "checkmark" : "arrow.triangle.branch")
                }
            }
            if !branches.isEmpty { Divider() }
            Button { newBranchName = ""; showNewBranch = true } label: {
                Label(model.t("code.branch.new"), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                Text(branch ?? model.t("code.branch.none")).font(.sfCaption2.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(gitBusy || pushing)
    }

    private func switchBranch(_ b: String) {
        guard b != branch, let repo = vm.config.repoPath else { return }
        gitBusy = true; gitError = nil
        Task {
            let r = await CodeGit.checkout(repo: repo, branch: b)
            if r.ok { branch = b; await loadDiff(); await refreshPR() } else { gitError = r.out }
            gitBusy = false
        }
    }

    private func createNewBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty, let repo = vm.config.repoPath else { return }
        gitBusy = true; gitError = nil
        Task {
            let r = await CodeGit.createBranch(repo: repo, name: name)
            if r.ok { branch = name; branches = await CodeGit.branches(repo: repo) } else { gitError = r.out }
            gitBusy = false
        }
    }

    /// One tap: commit everything with the drafted message, push, then open — or update,
    /// if one already exists — the branch's PR. Also the engine behind Auto-PR.
    private func commitAndPR(auto: Bool = false) {
        guard let repo = vm.config.repoPath, !pushing, !gitBusy else { return }
        let drafted = commitMessage.trimmingCharacters(in: .whitespaces).isEmpty ? draftMessage() : commitMessage
        let message = drafted.isEmpty ? "Update" : drafted
        let hadPR = pr != nil
        pushing = true; gitError = nil
        Task {
            // Auto flow always commits all; a manual tap respects staging when the user set it.
            let commit = (auto || staged.isEmpty)
                ? await CodeGit.commit(repo: repo, message: message)
                : await CodeGit.commitStaged(repo: repo, message: message)
            // "nothing to commit" is fine (there may already be commits to PR); only a
            // real error stops us.
            if !commit.ok, !commit.out.localizedCaseInsensitiveContains("nothing to commit") {
                gitError = commit.out; pushing = false; return
            }
            commitMessage = ""
            let push = await CodeGit.push(repo: repo)
            guard push.ok else { gitError = push.out; pushing = false; return }
            // A PR already open for this branch? The push updated it — don't try to open a
            // second (gh would error). Otherwise open one.
            if hadPR {
                model.flashSuccess(model.t("code.pr.updated"))
            } else {
                let pr = await GitHubCLI.createPR(repo: repo, title: message, body: prBody())
                if pr.ok { prURL = pr.url; model.flashSuccess(model.t("code.pr.opened")) }
                else { gitError = pr.out }
            }
            await loadDiff(); await loadChangeStats()
            staged = await CodeGit.stagedFiles(repo: repo)
            branch = await CodeGit.currentBranch(repo: repo)
            await refreshPR()
            pushing = false
        }
    }

    /// Push the current branch to origin and open a pull request via `gh`.
    private func pushAndPR() {
        guard let repo = vm.config.repoPath, !pushing else { return }
        pushing = true; gitError = nil; prURL = nil
        Task {
            let push = await CodeGit.push(repo: repo)
            guard push.ok else { gitError = push.out; pushing = false; return }
            let title = (commitMessage.isEmpty ? draftMessage() : commitMessage)
            let pr = await GitHubCLI.createPR(repo: repo,
                                              title: title.isEmpty ? "Update" : title,
                                              body: prBody())
            if pr.ok {
                prURL = pr.url
                model.flashSuccess(model.t("code.pr.opened"))
                await refreshPR()
            } else {
                gitError = pr.out
            }
            pushing = false
        }
    }

    /// Re-read the current branch's PR state (open/merged/closed) for the status bar.
    private func refreshPR() async {
        guard let repo = vm.config.repoPath, let b = branch, GitHubCLI.isInstalled else { pr = nil; return }
        pr = await GitHubCLI.prInfo(repo: repo, branch: b)
    }

    /// Merge the current branch's PR (squash) via gh, then refresh its state.
    private func mergePR() {
        guard let repo = vm.config.repoPath, let b = branch, !merging else { return }
        merging = true; gitError = nil
        Task {
            let r = await GitHubCLI.mergePR(repo: repo, branch: b)
            if r.ok { model.flashSuccess(model.t("code.pr.merged")) } else { gitError = r.out }
            await refreshPR()
            merging = false
        }
    }

    /// A compact status bar for the branch's pull request: state badge, number + title,
    /// links to the PR and its diff, and a one-tap merge when it's open.
    @ViewBuilder
    private var prStatusBar: some View {
        if let pr {
            let state = pr.isDraft ? "DRAFT" : pr.state.uppercased()
            Divider()
            HStack(spacing: Space.s) {
                Label {
                    Text(state.capitalized).font(.sfCaption2.weight(.semibold))
                } icon: {
                    Image(systemName: prIcon(state)).font(.system(size: 11))
                }
                .foregroundStyle(prColor(state))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(prColor(state).opacity(0.14)))

                Text("#\(pr.number)").font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(pr.title).font(.sfCaption2).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.s)

                if let url = URL(string: pr.url) {
                    Link(destination: url.appendingPathComponent("files")) {
                        Label(model.t("code.pr.diff"), systemImage: "plus.forwardslash.minus").font(.sfCaption2)
                    }
                    Link(destination: url) {
                        Label(model.t("code.viewPR"), systemImage: "arrow.up.forward.square").font(.sfCaption2)
                    }
                }
                if merging { WorkingLogo(size: 14) }
                if state == "OPEN" {
                    Button(model.t("code.pr.merge")) { mergePR() }
                        .controlSize(.small).buttonStyle(.moon).disabled(merging)
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(.bar)
        }
    }

    private func prIcon(_ state: String) -> String {
        switch state {
        case "MERGED": return "arrow.triangle.merge"
        case "CLOSED": return "xmark.circle"
        case "DRAFT": return "pencil.circle"
        default: return "arrow.triangle.pull"   // OPEN
        }
    }
    private func prColor(_ state: String) -> Color {
        switch state {
        case "MERGED": return Theme.accent
        case "CLOSED": return Theme.danger
        case "DRAFT": return .secondary
        default: return Theme.success   // OPEN
        }
    }

    /// Draft the PR body from the agent's last summary (best effort), with a footer.
    private func prBody() -> String {
        let summary = (vm.messages.last(where: { $0.role == .assistant })?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = summary.count > 1200 ? String(summary.prefix(1200)) + "…" : summary
        let footer = "\n\n— " + model.t("code.pr.body")
        return capped.isEmpty ? model.t("code.pr.body") : capped + footer
    }

    /// Draft a commit message from the agent's last reply (editable by the user).
    private func draftMessage() -> String {
        guard let last = vm.messages.last(where: { $0.role == .assistant })?.text else { return "" }
        let firstLine = last.split(separator: "\n").first.map(String.init) ?? last
        let clean = firstLine.trimmingCharacters(in: .whitespaces)
        let capped = clean.count > 64 ? String(clean.prefix(64)) + "…" : clean
        return capped.isEmpty ? "" : capped
    }

    private func icon(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "pdf": return "photo"
        default: return "doc"
        }
    }
}

/// Renders a parsed unified diff with line numbers and add/remove coloring.
struct DiffScrollView: View {
    let lines: [DiffLine]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in row(line) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.s)
        }
    }

    private func row(_ l: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(l.oldNumber)
            gutter(l.newNumber)
            Text(prefix(l) + l.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(fg(l))
                .textSelection(.enabled)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(bg(l))
    }

    private func gutter(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 38, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private func prefix(_ l: DiffLine) -> String {
        switch l.kind { case .add: return "+ "; case .del: return "- "; case .hunk: return ""; case .context: return "  " }
    }
    private func fg(_ l: DiffLine) -> Color {
        switch l.kind {
        case .add: return Theme.success
        case .del: return Theme.danger
        case .hunk: return Theme.accent
        case .context: return .primary
        }
    }
    private func bg(_ l: DiffLine) -> Color {
        switch l.kind {
        case .add: return Theme.success.opacity(0.10)
        case .del: return Theme.danger.opacity(0.10)
        case .hunk: return Theme.accent.opacity(0.08)
        case .context: return .clear
        }
    }
}
