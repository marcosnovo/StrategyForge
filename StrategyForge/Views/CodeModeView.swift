//
//  CodeModeView.swift
//  StrategyForge
//
//  A developer workspace shown in place of the chat transcript when Code Mode is
//  on: the files the agent changed on the left, the selected file's contents on the
//  right. Phase 1 (browse + view). Diffs, terminal and git land in later phases.
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
    // Branch switching
    @State private var branches: [String] = []
    @State private var showNewBranch = false
    @State private var newBranchName = ""
    // Per-file staging (absolute paths, matching editedFiles)
    @State private var staged: Set<String> = []

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
            Task {
                if let repo = vm.config.repoPath {
                    branch = await CodeGit.currentBranch(repo: repo)
                    branches = await CodeGit.branches(repo: repo)
                }
            }
        }
        .onChange(of: vm.editedFiles) { _, new in
            if selected == nil || !(new.contains(selected ?? "")) { selected = new.first }
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
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(isSel ? Theme.accentSoft : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        if loadingDiff { DotSpinner(size: 16) }
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
                if gitBusy || pushing { DotSpinner(size: 16) }
                Button(model.t("code.commit")) { confirmCommit = true }
                    .buttonStyle(.moon)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || gitBusy || pushing)
                // One tap to push the branch and open a PR (needs the gh CLI).
                if GitHubCLI.isInstalled {
                    Button { pushAndPR() } label: {
                        Label(model.t("code.pushPR"), systemImage: "arrow.up.right.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(gitBusy || pushing)
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
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
            if r.ok { branch = b; await loadDiff() } else { gitError = r.out }
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
            } else {
                gitError = pr.out
            }
            pushing = false
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
