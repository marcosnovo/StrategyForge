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
    @AppStorage("code.diffSplit") private var diffSplit = false

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

    /// Files the reviewer has marked "viewed" — a Claude/GitHub-style review-progress signal.
    /// Session-local (a review is a moment, not a persisted fact); reset when the file set changes.
    @State private var viewed: Set<String> = []

    /// Scroll the diff to a given new-file line (set when a review finding is clicked); a
    /// pending value survives a file switch until the new diff has loaded.
    @State private var scrollRequest: Int?
    @State private var pendingScroll: Int?
    /// Index into the current file's changed hunks, for prev/next-hunk navigation.
    @State private var currentHunk = 0
    /// The launch-checklist sheet for this project (empty repo → shipped).
    @State private var showChecklist = false
    /// The floating "agents" companion over the diff — expanded shows the live team graph, so
    /// you can watch the agents work AND read their diff at once (they used to be mutually
    /// exclusive right-hand columns). Collapsed to a pill; persisted.
    @AppStorage("code.agentsExpanded") private var agentsExpanded = true
    /// Active review-severity filter (nil = show every tier). Tapping a tier chip focuses it.
    @State private var reviewFilter: ReviewSeverity?

    /// Above this many diff lines we don't auto-render the (word-diffed, min-width-pinned) diff —
    /// the reviewer opts in per file, so a giant generated file can't jank the workspace.
    static let largeDiffThreshold = 2500
    @State private var forceRenderLargeDiff = false

    /// Session checkpoints: non-destructive snapshots (git stash create) you can rewind to.
    @State private var checkpoints: [Checkpoint] = []
    @State private var confirmRestore: Checkpoint?
    struct Checkpoint: Identifiable, Equatable {
        let id = UUID()
        let sha: String
        let label: String
        let at: Date
    }

    private var isRepo: Bool { !(vm.config.repoPath ?? "").isEmpty }

    private var files: [String] { vm.editedFiles }

    var body: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: 240)
                .background(keyboardShortcuts)
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
            viewed.formIntersection(new)   // drop files that are no longer in the change set
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
        .onChange(of: selected) { currentHunk = 0; forceRenderLargeDiff = false; Task { await loadDiff() } }
        .confirmationDialog(model.t("code.revertConfirm"), isPresented: revertBinding, titleVisibility: .visible) {
            Button(model.t("code.revert"), role: .destructive) { performRevert() }
            Button(model.t("common.cancel"), role: .cancel) { confirmRevert = nil }
        }
        .confirmationDialog(model.t("code.commitConfirm"), isPresented: $confirmCommit, titleVisibility: .visible) {
            Button(model.t("code.commit")) { performCommit() }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showChecklist) { LaunchChecklistView(projectID: vm.config.id) }
        .confirmationDialog(model.t("code.checkpoint.restoreConfirm"),
                            isPresented: Binding(get: { confirmRestore != nil },
                                                 set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button(model.t("code.checkpoint.rewind"), role: .destructive) {
                if let cp = confirmRestore { performRestore(cp) }
            }
            Button(model.t("common.cancel"), role: .cancel) { confirmRestore = nil }
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
        // A finding-jump that switched files waits for the diff to load, then scrolls.
        if let pending = pendingScroll {
            pendingScroll = nil
            viewMode = .diff
            scrollRequest = pending
        }
    }

    /// Reviewer findings pinned to the currently-selected file, keyed by new-file line →
    /// highest severity on that line (for the gutter markers).
    private var findingLinesForSelected: [Int: ReviewSeverity] {
        guard let sel = selected, let review = model.diffReview else { return [:] }
        let selName = (sel as NSString).lastPathComponent
        var map: [Int: ReviewSeverity] = [:]
        for f in review.findings {
            guard let line = f.line, !f.file.isEmpty else { continue }
            // Match on full path or basename — the model may pin either.
            let fName = (f.file as NSString).lastPathComponent
            guard sel.hasSuffix(f.file) || f.file.hasSuffix(sel) || fName == selName else { continue }
            if let existing = map[line], existing.rank <= f.severity.rank { continue }
            map[line] = f.severity
        }
        return map
    }

    /// The current file's hunks that actually carry a change — the units of hunk navigation.
    private var changedHunks: [DiffHunk] {
        guard let diff = diffLines else { return [] }
        return DiffHunks.group(diff).filter(\.hasChange)
    }

    /// Step to the previous/next changed hunk and scroll it into view.
    private func stepHunk(_ delta: Int) {
        let hunks = changedHunks
        guard !hunks.isEmpty else { return }
        currentHunk = (currentHunk + delta + hunks.count) % hunks.count
        if let line = hunks[currentHunk].anchorNewLine { scrollRequest = line }
    }

    /// Invisible buttons that carry the diff-review keyboard shortcuts. All use ⌥ (Option) so
    /// they never fire while the user is typing in the commit field. Active only while Code mode
    /// is on screen (this view is mounted). ⌥[ / ⌥] file · ⌥↑ / ⌥↓ hunk · ⌥V viewed · ⌥D split.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { stepFile(-1) }.keyboardShortcut("[", modifiers: [.option])
            Button("") { stepFile(1) }.keyboardShortcut("]", modifiers: [.option])
            Button("") { stepHunk(-1) }.keyboardShortcut(.upArrow, modifiers: [.option])
            Button("") { stepHunk(1) }.keyboardShortcut(.downArrow, modifiers: [.option])
            Button("") { toggleViewedSelected() }.keyboardShortcut("v", modifiers: [.option])
            Button("") { diffSplit.toggle() }.keyboardShortcut("d", modifiers: [.option])
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// Step selection to the previous/next changed file (⌥[ / ⌥]).
    private func stepFile(_ delta: Int) {
        guard !files.isEmpty else { return }
        let idx = files.firstIndex(of: selected ?? "") ?? 0
        let next = (idx + delta + files.count) % files.count
        selected = files[next]
    }

    /// Toggle "viewed" on the currently-selected file (⌥V).
    private func toggleViewedSelected() {
        if let sel = selected { toggleViewed(sel) }
    }

    /// Repo-relative path of the selected file (git apply needs `a/<rel>` paths).
    private func relPath(for absPath: String) -> String? {
        guard let repo = vm.config.repoPath, absPath.hasPrefix(repo) else { return nil }
        return String(absPath.dropFirst(repo.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Stage (cached) or discard (reverse, working tree) just the current hunk via a
    /// reconstructed single-hunk patch. On failure, surface git's own message.
    private func applyCurrentHunk(reverse: Bool) {
        let hunks = changedHunks
        guard hunks.indices.contains(currentHunk),
              let sel = selected, let rel = relPath(for: sel),
              let patch = hunks[currentHunk].unifiedPatch(relPath: rel),
              let repo = vm.config.repoPath else { return }
        gitBusy = true; gitError = nil
        Task {
            let r = await CodeGit.applyHunkPatch(repo: repo, patch: patch, reverse: reverse, cached: !reverse)
            if r.ok {
                if reverse { await loadDiff() }          // working tree changed → re-read
                staged = await CodeGit.stagedFiles(repo: repo)
                await loadChangeStats()
                currentHunk = min(currentHunk, max(0, changedHunks.count - 1))
            } else {
                gitError = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            gitBusy = false
        }
    }

    /// Jump the diff to a finding: switch to its file if needed (scroll applies once the diff
    /// loads), otherwise scroll straight away.
    private func jumpToFinding(_ f: ReviewFinding) {
        guard let line = f.line else { return }
        let selName = (selected as NSString?)?.lastPathComponent
        let sameFile = f.file.isEmpty
            || (selected.map { $0.hasSuffix(f.file) || f.file.hasSuffix($0) } ?? false)
            || (f.file as NSString).lastPathComponent == selName
        if sameFile {
            viewMode = .diff
            scrollRequest = line
        } else if let match = files.first(where: { $0.hasSuffix(f.file) || f.file.hasSuffix($0) || ($0 as NSString).lastPathComponent == (f.file as NSString).lastPathComponent }) {
            pendingScroll = line
            selected = match   // triggers loadDiff → applies pendingScroll
        }
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
                if !files.isEmpty { reviewProgress }
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

    /// Review-progress: how many changed files the reviewer has marked "viewed", as a slim bar
    /// plus an "n/total" count and a reset. Mirrors GitHub's "Viewed" review flow.
    private var reviewProgress: some View {
        let total = files.count
        let done = files.filter(viewed.contains).count
        let frac = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(model.t("code.reviewed")).font(.sfCaption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(done)/\(total)").font(.sfCaption2.weight(.medium))
                    .foregroundStyle(done == total ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary))
                if done > 0 {
                    Button { viewed.removeAll() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 9))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help(model.t("code.reviewed.reset"))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(done == total ? Theme.success : Theme.coral)
                        .frame(width: max(0, geo.size.width * frac))
                        .animation(.easeOut(duration: 0.25), value: frac)
                }
            }
            .frame(height: 3)
        }
    }

    private func fileRow(_ path: String) -> some View {
        let isSel = selected == path
        let isStaged = staged.contains(path)
        let isViewed = viewed.contains(path)
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
                        .strikethrough(isViewed, color: Theme.ink.opacity(0.35))
                    // Who wrote it: a provider-tinted dot, tooltip = "Agent · Model".
                    provenanceDot(for: path)
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
            .opacity(isViewed && !isSel ? 0.5 : 1)
            // Mark-viewed toggle (eye) — the reviewer's "I've seen this file" checkmark.
            Button { toggleViewed(path) } label: {
                Image(systemName: isViewed ? "eye.fill" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(isViewed ? AnyShapeStyle(Theme.coral) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help(model.t(isViewed ? "code.unview" : "code.view"))
        }
    }

    private func toggleViewed(_ path: String) {
        if viewed.contains(path) { viewed.remove(path) } else { viewed.insert(path) }
    }

    /// A compact "+12 −3" with an M/A/D/U kind letter, so each file shows how much it
    /// changed at a glance (Claude-style).
    @ViewBuilder
    private func changeBadge(_ s: CodeGit.ChangedFile) -> some View {
        HStack(spacing: 4) {
            if s.insertions > 0 {
                Text("+\(s.insertions)").scaledFont(9, weight: .semibold, design: .monospaced)
                    .foregroundStyle(Theme.success)
            }
            if s.deletions > 0 {
                Text("−\(s.deletions)").scaledFont(9, weight: .semibold, design: .monospaced)
                    .foregroundStyle(Theme.danger)
            }
            Text(kindLetter(s.kind))
                .scaledFont(8, weight: .bold, design: .monospaced)
                .foregroundStyle(kindColor(s.kind))
                .frame(width: 12, height: 12)
                .background(RoundedRectangle(cornerRadius: 3).fill(kindColor(s.kind).opacity(0.15)))
        }
    }

    /// The orchestrator's display name, used to label edits it made itself.
    private var orchestratorName: String {
        vm.config.strategy.orchestrator?.name ?? model.t("code.orchestrator")
    }

    /// Per-line authors for the selected file, keyed by 1-based new-file line number (to
    /// match `DiffLine.newNumber`), so the diff can tint each added line by who wrote it.
    private func lineAuthors(for path: String?) -> [Int: EditProvenance] {
        guard let path, let authors = vm.lineProvenance[path] else { return [:] }
        var map: [Int: EditProvenance] = [:]
        for (i, a) in authors.enumerated() { if let a { map[i + 1] = a } }
        return map
    }

    /// A small provider-tinted dot crediting the agent that wrote this file, with the
    /// full "Agent · Model" in the tooltip. Nothing when the file has no provenance
    /// (e.g. restored from a past session — provenance is live, not persisted).
    @ViewBuilder
    private func provenanceDot(for path: String) -> some View {
        if let p = vm.fileProvenance[path] {
            let orch = orchestratorName
            Circle()
                .fill(p.provider.tint)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.background, lineWidth: 0.5))
                .help(p.label(orchestratorName: orch))
                .accessibilityLabel(Text("\(model.t("code.writtenBy")): \(p.label(orchestratorName: orch))"))
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

    /// Shown instead of a very large diff — render is opt-in so a huge generated file doesn't
    /// build a giant lazy stack + word-diff on open. Opening the file directly is always offered.
    private func largeDiffNotice(_ lineCount: Int) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: "doc.badge.ellipsis").font(.title2).foregroundStyle(.tertiary)
            Text(model.t("code.largeDiff", lineCount)).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.s) {
                Button(model.t("code.largeDiff.show")) { forceRenderLargeDiff = true }
                    .buttonStyle(.bordered).controlSize(.small)
                if let path = selected {
                    Button(model.t("filepreview.open")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.l)
    }

    // MARK: Right — file viewer

    private var fileViewer: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if vm.isRunning { runStatusBar }   // never look frozen during a run
                fileViewerBody
            }
            agentsCompanion   // floating team graph, top-right, over the diff
        }
    }

    /// Toolbar entry to the launch checklist. Shows the done/total fraction as a badge once a
    /// checklist exists, so shipping progress is visible at a glance.
    @ViewBuilder private var checklistToolbarButton: some View {
        let list = ChecklistStore.shared.checklist(forProject: vm.config.id)
        Button { showChecklist = true } label: {
            HStack(spacing: 4) {
                Image(systemName: list?.isComplete == true ? "checkmark.seal.fill" : "checklist")
                if let list, list.totalItems > 0 {
                    Text("\(list.doneItems)/\(list.totalItems)").font(.sfFieldLabel).monospacedDigit()
                }
            }
            .foregroundStyle(list?.isComplete == true ? Theme.success : .secondary)
        }
        .buttonStyle(.plain).help(model.t("checklist.help"))
    }

    /// A prominent "the team is working" bar shown across the top of the code workspace during a
    /// live run — brand spinner + live elapsed counter + the newest narration/tool line. This is
    /// the fix for "it feels like it does nothing": the diff pane stays empty until files are
    /// written (which can be minutes of planning), so without this the workspace looks frozen.
    private var runStatusBar: some View {
        HStack(spacing: Space.s) {
            WorkingLine(label: liveStatusLabel)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft.opacity(0.5))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The newest sign of life to show in the status bar: a running role's live narration, else
    /// the last activity step, else a generic "working" line.
    private var liveStatusLabel: String {
        if let line = vm.roleLiveLine.values.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return line
        }
        if let step = vm.timeline.last {
            if let d = step.detail, !d.isEmpty { return "\(step.title): \(d)" }
            return step.title
        }
        if !vm.rolesInProgress.isEmpty { return model.t("code.working.agents") }
        return model.t("code.working")
    }

    private var fileViewerBody: some View {
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
                            .pickerStyle(.segmented).tint(Theme.coral).labelsHidden().fixedSize()
                            // Unified ↔ split (side-by-side) toggle — only meaningful in diff mode.
                            if viewMode == .diff {
                                Button { diffSplit.toggle() } label: {
                                    Image(systemName: diffSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(diffSplit ? Theme.coral : .secondary)
                                .help(model.t(diffSplit ? "code.diff.unified" : "code.diff.split"))
                                // Prev / next changed hunk — jump between change blocks.
                                let hunkCount = changedHunks.count
                                if hunkCount > 1 {
                                    Button { stepHunk(-1) } label: { Image(systemName: "chevron.up") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                        .help(model.t("code.hunk.prev"))
                                    Text("\(min(currentHunk + 1, hunkCount))/\(hunkCount)")
                                        .font(.sfFieldLabel).foregroundStyle(.tertiary).monospacedDigit()
                                    Button { stepHunk(1) } label: { Image(systemName: "chevron.down") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                        .help(model.t("code.hunk.next"))
                                    // Stage / discard JUST the current hunk (single-hunk patch).
                                    if isRepo, relPath(for: selected ?? "") != nil {
                                        Button { applyCurrentHunk(reverse: false) } label: {
                                            Image(systemName: "plus.circle")
                                        }
                                        .buttonStyle(.plain).foregroundStyle(Theme.success)
                                        .disabled(gitBusy).help(model.t("code.hunk.stage"))
                                        Button { applyCurrentHunk(reverse: true) } label: {
                                            Image(systemName: "arrow.uturn.backward.circle")
                                        }
                                        .buttonStyle(.plain).foregroundStyle(Theme.danger)
                                        .disabled(gitBusy).help(model.t("code.hunk.revert"))
                                    }
                                }
                            }
                        }
                        // Launch checklist for this project (empty repo → shipped).
                        checklistToolbarButton
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
                        if diff.count > Self.largeDiffThreshold && !forceRenderLargeDiff {
                            largeDiffNotice(diff.count)
                        } else if diffSplit {
                            SplitDiffScrollView(lines: diff,
                                                fileExtension: ((selected ?? "") as NSString).pathExtension)
                        } else {
                            DiffScrollView(lines: diff, lineAuthors: lineAuthors(for: selected),
                                           orchestratorName: orchestratorName,
                                           fileExtension: ((selected ?? "") as NSString).pathExtension,
                                           findingLines: findingLinesForSelected,
                                           scrollRequest: $scrollRequest)
                        }
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
                    if isRepo, let review = model.diffReview { reviewPanel(review) }
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

    /// A floating, collapsible companion that keeps the live team graph in view while you read
    /// the diff — the diff stays the full-width primary surface; the agents view is a quiet,
    /// dismissible overlay instead of a column that evicts it. Only shown when there's a team
    /// (or a live run), so solo/idle code sessions keep quiet chrome.
    @ViewBuilder private var agentsCompanion: some View {
        let hasTeam = !vm.config.strategy.subagentRoles.isEmpty
        if hasTeam || vm.isRunning {
            VStack(alignment: .trailing, spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { agentsExpanded.toggle() } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(vm.isRunning ? Theme.teal : Theme.inkDim)
                            .frame(width: 6, height: 6)
                        Text(model.t("code.agents")).font(.sfCaption2.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: agentsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t(agentsExpanded ? "code.agents.hide" : "code.agents.show"))
                if agentsExpanded || vm.isRunning {   // always reveal the live graph during a run
                    Divider().frame(width: 300)
                    Group {
                        if vm.isRunning {
                            LiveAgentGraphView(snapshot: vm.liveGraph).frame(width: 300, height: 210)
                        } else {
                            StrategyDiagramView(strategy: vm.config.strategy,
                                                activeAgent: vm.activeSubagent,
                                                isLive: false, compact: true)
                                .frame(width: 300, height: 210)
                        }
                    }
                    .padding(8)
                }
            }
            .glassPanel(cornerRadius: Theme.corner)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .elevation(.e3)
            .padding(Space.m)
        }
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
                    Image(systemName: showTerminal ? "chevron.down" : "chevron.up").scaledFont(9)
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

    /// The automated diff-review findings (independent read-only reviewer).
    /// Promote review findings into the knowledge base as pitfalls-to-avoid. Global scope
    /// (a real bug is worth avoiding everywhere), tagged with the repo so tag-overlap
    /// surfaces them strongly on the same project. Honest source: `.review`.
    private func promoteFindingsToMemory(_ findings: [ReviewFinding]) {
        let repoTag = (vm.config.repoPath).flatMap { $0.isEmpty ? nil : ($0 as NSString).lastPathComponent.lowercased() }
        for f in findings {
            let where_ = f.file.isEmpty ? f.severity.rawValue
                : "\((f.file as NSString).lastPathComponent) · \(f.severity.rawValue)"
            MemoryStore.shared.add(Learning(
                kind: .mistake, title: f.title, body: f.detail,
                tags: [repoTag].compactMap { $0 },
                source: LearningSource(origin: .review, detail: where_)))
        }
        model.flashSuccess(model.t("review.saveMemoryDone", findings.count))
    }

    private func reviewPanel(_ review: DiffReview) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Divider()
            HStack(spacing: Space.s) {
                if let error = review.error {
                    // The reviewer itself failed — never dress that up as "no issues".
                    Label("\(model.t("review.action")): \(error)", systemImage: "xmark.seal.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if review.isClean {
                    Label(model.t("review.clean"), systemImage: "checkmark.seal.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.success)
                } else {
                    Label(model.t("review.foundIssues", review.findings.count),
                          systemImage: review.hasBlocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.sfCaption2.weight(.semibold))
                        .foregroundStyle(review.hasBlocking ? Theme.danger : Theme.warning)
                }
                Spacer()
                // Close the loop (opt-in): hand the findings back to the author team to
                // fix in place. Only when there's something actionable and the reviewer
                // actually ran (a failed review has nothing to fix).
                if review.error == nil, !review.findings.isEmpty {
                    Button {
                        vm.requestReviewFixes(review.findings)
                        model.diffReview = nil
                        model.flashSuccess(model.t("review.fixSent"))
                    } label: {
                        Label(model.t("review.fix"), systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(model.t("review.fixHint"))
                    // Distil the findings into the cross-project knowledge base, so the
                    // same pitfalls get flagged in future teams' CLAUDE.md.
                    Button {
                        promoteFindingsToMemory(review.findings)
                    } label: {
                        Label(model.t("review.saveMemory"), systemImage: "brain")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(model.t("review.saveMemoryHint"))
                }
                // No verifier seal on a failed run — nothing was verified.
                if review.error == nil { IndependentVerifierSeal(style: .compact) }
                Button { model.diffReview = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            // Severity tier chips — counts per tier, tap to focus one tier (tap again = all).
            if review.error == nil, review.findings.count > 1 {
                HStack(spacing: Space.xs) {
                    ForEach(ReviewSeverity.allCases, id: \.self) { sev in
                        let n = review.findings.filter { $0.severity == sev }.count
                        if n > 0 { tierChip(sev, count: n) }
                    }
                    if reviewFilter != nil {
                        Button(model.t("review.tier.all")) { reviewFilter = nil }
                            .buttonStyle(.plain).font(.sfFieldLabel).foregroundStyle(Theme.coral)
                    }
                    Spacer()
                }
            }
            ForEach(review.findings.filter { reviewFilter == nil || $0.severity == reviewFilter }) { f in
                let jumpable = f.line != nil && !f.file.isEmpty
                HStack(alignment: .top, spacing: Space.s) {
                    // Severity marker by shape+color (colorblind-safe).
                    severityMarker(f.severity).frame(width: 9, height: 9).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: Space.xs) {
                            Text(f.title).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.ink)
                            if !f.file.isEmpty {
                                Text(f.line.map { "\((f.file as NSString).lastPathComponent):\($0)" } ?? (f.file as NSString).lastPathComponent)
                                    .font(.sfFieldLabel).foregroundStyle(jumpable ? AnyShapeStyle(Theme.coral) : AnyShapeStyle(.tertiary))
                            }
                            if jumpable {
                                Image(systemName: "arrow.right.circle").font(.system(size: 9)).foregroundStyle(Theme.coral.opacity(0.7))
                            }
                        }
                        if !f.detail.isEmpty {
                            Text(f.detail).font(.sfCaption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { if jumpable { jumpToFinding(f) } }
                .help(jumpable ? model.t("review.jump") : "")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(model.t(f.severity.labelKey)): \(f.title). \(f.detail)")
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(Theme.chromeBg)
    }

    @ViewBuilder private func severityMarker(_ s: ReviewSeverity) -> some View {
        switch s {
        case .high:   RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.danger)
        case .medium: Circle().fill(Theme.warning)
        case .low:    Circle().strokeBorder(Theme.inkDim, lineWidth: 1.5)
        }
    }

    /// A tappable severity-tier chip: dot + tier label + count. Active tier is filled; tapping
    /// toggles the filter between "this tier only" and "all".
    private func tierChip(_ sev: ReviewSeverity, count: Int) -> some View {
        let active = reviewFilter == sev
        return Button {
            reviewFilter = active ? nil : sev
        } label: {
            HStack(spacing: 4) {
                severityMarker(sev).frame(width: 8, height: 8)
                Text(model.t(sev.labelKey)).font(.sfFieldLabel)
                Text("\(count)").font(.sfFieldLabel.weight(.semibold)).monospacedDigit()
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(active ? sev.tint.opacity(0.16) : Theme.insetBg))
            .overlay(Capsule().strokeBorder(active ? sev.tint.opacity(0.5) : .clear, lineWidth: 1))
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
    }

    /// Checkpoints: capture a non-destructive snapshot, or rewind to a past one. A safety net
    /// for reviewing agent work — snapshot before you accept, roll back if it went wrong.
    private var checkpointMenu: some View {
        Menu {
            Button {
                Task { await captureCheckpoint() }
            } label: { Label(model.t("code.checkpoint.capture"), systemImage: "camera.aperture") }
            .disabled(gitBusy)
            if !checkpoints.isEmpty {
                Divider()
                Text(model.t("code.checkpoint.rewindTo")).font(.sfFieldLabel)
                ForEach(checkpoints.reversed()) { cp in
                    Button {
                        confirmRestore = cp
                    } label: {
                        Label("\(cp.label) · \(cp.at.formatted(date: .omitted, time: .shortened))",
                              systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        } label: {
            Label(model.t("code.checkpoint"), systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(model.t("code.checkpoint.help"))
    }

    private func captureCheckpoint() async {
        guard let repo = vm.config.repoPath else { return }
        gitBusy = true; gitError = nil
        if let sha = await CodeGit.createCheckpoint(repo: repo) {
            let n = checkpoints.count + 1
            checkpoints.append(Checkpoint(sha: sha, label: model.t("code.checkpoint.label", n), at: Date()))
            model.flashSuccess(model.t("code.checkpoint.saved"))
        } else {
            gitError = model.t("code.checkpoint.empty")
        }
        gitBusy = false
    }

    private func performRestore(_ cp: Checkpoint) {
        guard let repo = vm.config.repoPath else { return }
        confirmRestore = nil; gitBusy = true; gitError = nil
        Task {
            let r = await CodeGit.restoreCheckpoint(repo: repo, sha: cp.sha)
            if r.ok {
                await loadDiff(); await loadChangeStats()
                model.flashSuccess(model.t("code.checkpoint.restored"))
            } else {
                gitError = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            gitBusy = false
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
                if gitBusy || pushing || model.isReviewingDiff { WorkingLogo(size: 16) }
                // Independent read-only review of the working diff before you commit/PR.
                Button { Task { await model.reviewChanges(for: vm.config) } } label: {
                    Label(model.t("review.action"), systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(gitBusy || pushing || model.isReviewingDiff)
                checkpointMenu
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
        .background(Theme.chromeBg)
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
                Image(systemName: "arrow.triangle.branch").scaledFont(9)
                Text(branch ?? model.t("code.branch.none")).font(.sfCaption2.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").scaledFont(7)
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
            .background(Theme.chromeBg)
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

/// Renders a parsed unified diff with line numbers and add/remove coloring. Rows are
/// built LAZILY — a large diff would otherwise construct thousands of views
/// synchronously on the main thread and freeze Code Mode.
struct DiffScrollView: View {
    let lines: [DiffLine]
    /// Author of each added line, keyed by 1-based new-file line number. Empty = no
    /// provenance captured (e.g. a file restored from a past session).
    var lineAuthors: [Int: EditProvenance] = [:]
    var orchestratorName: String = ""
    /// The file's extension, for syntax highlighting the diff body.
    var fileExtension: String = ""
    /// Reviewer findings pinned to new-file line numbers → a severity marker in the gutter.
    var findingLines: [Int: ReviewSeverity] = [:]
    /// Set to a new-file line number to scroll that line into view; cleared once handled.
    @Binding var scrollRequest: Int?
    /// Word-level intraline change ranges (character offsets) per line id — computed once from the
    /// paired del/add runs so the row can emphasise ONLY the tokens that actually changed.
    private let emphasis: [DiffLine.ID: Range<Int>]

    init(lines: [DiffLine], lineAuthors: [Int: EditProvenance] = [:],
         orchestratorName: String = "", fileExtension: String = "",
         findingLines: [Int: ReviewSeverity] = [:], scrollRequest: Binding<Int?> = .constant(nil)) {
        self.lines = lines
        self.lineAuthors = lineAuthors
        self.orchestratorName = orchestratorName
        self.fileExtension = fileExtension
        self.findingLines = findingLines
        self._scrollRequest = scrollRequest
        self.emphasis = DiffEmphasis.compute(lines)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in row(line) }
                }
                // Lazy rows can't size to offscreen peers, so pin the stack's width to the
                // widest line up front — keeping horizontal scrolling coherent.
                .frame(minWidth: minRowWidth, maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.s)
            }
            .onChange(of: scrollRequest) { _, req in
                guard let req, let target = lineID(forNewLine: req) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
                scrollRequest = nil
            }
        }
    }

    /// The row id (DiffLine.id) whose new-file number is `n`, or the closest one at/after it —
    /// so a finding pinned to a context line still lands somewhere sensible.
    private func lineID(forNewLine n: Int) -> DiffLine.ID? {
        if let exact = lines.first(where: { $0.newNumber == n }) { return exact.id }
        return lines.filter { ($0.newNumber ?? -1) >= n }.min { ($0.newNumber ?? 0) < ($1.newNumber ?? 0) }?.id
    }

    /// Estimated width of the widest row: two gutters + leading pad + monospaced text
    /// (~7.3pt per character at 12pt; `utf8.count` is O(1) and only ever overestimates).
    private var minRowWidth: CGFloat {
        let maxChars = lines.reduce(0) { max($0, $1.text.utf8.count) }
        return 3 + 10 + 2 * (38 + 4) + 8 + CGFloat(maxChars + 2) * 7.3
    }

    private func row(_ l: DiffLine) -> some View {
        HStack(spacing: 0) {
            provenanceBar(l)
            findingMarker(l)
            gutter(l.oldNumber)
            gutter(l.newNumber)
            // The +/- marker stays coloured (fast to scan); the code body is syntax-highlighted
            // on ink, and the row's green/red BACKGROUND is what signals add vs delete — the SOTA
            // look (Zed/GitHub/VS Code), instead of flat all-green/all-red text.
            HStack(spacing: 0) {
                Text(prefix(l)).foregroundStyle(fg(l))
                body(l)
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(bg(l))
    }

    @ViewBuilder private func body(_ l: DiffLine) -> some View {
        switch l.kind {
        case .hunk:
            Text(l.text).foregroundStyle(Theme.accent)
        case .add, .del, .context:
            Text(highlighted(l))
        }
    }

    /// Syntax-highlighted line, with the changed tokens (word-level diff) washed stronger.
    private func highlighted(_ l: DiffLine) -> AttributedString {
        CodeSyntax.diffLine(l.text, ext: fileExtension, emphasis: emphasis[l.id], isDelete: l.kind == .del)
    }

    /// A reviewer-finding marker in the gutter: a small severity-tinted dot on any line a
    /// finding was pinned to, so issues are visible right where they live in the code.
    @ViewBuilder private func findingMarker(_ l: DiffLine) -> some View {
        if let n = l.newNumber, let sev = findingLines[n] {
            Circle().fill(sev.tint).frame(width: 6, height: 6)
                .frame(width: 10)
                .help(model_reviewTip)
        } else {
            Color.clear.frame(width: 10)
        }
    }
    // A static tip string (DiffScrollView has no model env); kept simple.
    private var model_reviewTip: String { "Reviewer finding" }

    /// A thin provider-tinted rail on each added line, crediting whoever wrote it (tooltip
    /// = "Agent · Model"). A clear rail keeps every row aligned when there's no author.
    @ViewBuilder private func provenanceBar(_ l: DiffLine) -> some View {
        if l.kind == .add, let n = l.newNumber, let a = lineAuthors[n] {
            Rectangle().fill(a.provider.tint).frame(width: 3)
                .help(a.label(orchestratorName: orchestratorName))
                .accessibilityLabel(Text(a.label(orchestratorName: orchestratorName)))
        } else {
            Color.clear.frame(width: 3)
        }
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

/// Side-by-side (split) diff — old on the left, new on the right, context on both. Built from the
/// flat DiffLine list by pairing each del run with the following add run, so the same syntax +
/// word-level highlighting applies. One shared vertical ScrollView keeps the two sides in sync.
struct SplitDiffScrollView: View {
    let lines: [DiffLine]
    var fileExtension: String = ""

    private let rows: [SideRow]
    private let emphasis: [DiffLine.ID: Range<Int>]

    init(lines: [DiffLine], fileExtension: String = "") {
        self.lines = lines
        self.fileExtension = fileExtension
        self.emphasis = DiffEmphasis.compute(lines)
        self.rows = Self.pair(lines)
    }

    struct SideRow: Identifiable {
        let id = UUID()
        var left: DiffLine?     // deleted / context (old side)
        var right: DiffLine?    // added / context (new side)
        var hunk: String?       // a full-width hunk header row
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { r in row(r) }
            }
            .padding(.vertical, Space.s)
        }
    }

    @ViewBuilder private func row(_ r: SideRow) -> some View {
        if let h = r.hunk {
            Text(h).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.accent)
                .padding(.vertical, 1).padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08))
        } else {
            HStack(spacing: 0) {
                cell(r.left, side: .left)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                cell(r.right, side: .right)
            }
        }
    }

    private enum Side { case left, right }
    @ViewBuilder private func cell(_ l: DiffLine?, side: Side) -> some View {
        HStack(spacing: 0) {
            Text((side == .left ? l?.oldNumber : l?.newNumber).map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing).padding(.trailing, 4)
            if let l {
                Text(CodeSyntax.diffLine(l.text, ext: fileExtension, emphasis: emphasis[l.id], isDelete: l.kind == .del))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cellBg(l, side: side))
    }

    private func cellBg(_ l: DiffLine?, side: Side) -> Color {
        guard let l else { return Theme.insetBg.opacity(0.25) }   // no counterpart → faint filler
        switch l.kind {
        case .del: return Theme.danger.opacity(0.10)
        case .add: return Theme.success.opacity(0.10)
        default:   return .clear
        }
    }

    /// Pair the flat diff into aligned left/right rows.
    private static func pair(_ lines: [DiffLine]) -> [SideRow] {
        var rows: [SideRow] = []
        var i = 0
        while i < lines.count {
            let l = lines[i]
            switch l.kind {
            case .hunk:
                rows.append(SideRow(hunk: l.text)); i += 1
            case .context:
                rows.append(SideRow(left: l, right: l)); i += 1
            case .del:
                var dels: [DiffLine] = []; var j = i
                while j < lines.count, lines[j].kind == .del { dels.append(lines[j]); j += 1 }
                var adds: [DiffLine] = []; var k = j
                while k < lines.count, lines[k].kind == .add { adds.append(lines[k]); k += 1 }
                let n = max(dels.count, adds.count)
                for p in 0..<n {
                    rows.append(SideRow(left: p < dels.count ? dels[p] : nil,
                                        right: p < adds.count ? adds[p] : nil))
                }
                i = k
            case .add:
                var adds: [DiffLine] = []; var k = i
                while k < lines.count, lines[k].kind == .add { adds.append(lines[k]); k += 1 }
                for a in adds { rows.append(SideRow(left: nil, right: a)) }
                i = k
            }
        }
        return rows
    }
}
