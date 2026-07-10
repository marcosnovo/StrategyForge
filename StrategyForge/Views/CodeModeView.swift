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
    @State private var loadingDiff = false
    @State private var viewMode: ViewMode = .diff
    enum ViewMode: String, CaseIterable { case diff, file }

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
        .onAppear { if selected == nil { selected = files.first }; Task { await loadDiff() } }
        .onChange(of: vm.editedFiles) { _, new in
            if selected == nil || !(new.contains(selected ?? "")) { selected = new.first }
        }
        .onChange(of: selected) { Task { await loadDiff() } }
    }

    private func loadDiff() async {
        guard let path = selected, let repo = vm.config.repoPath, !repo.isEmpty else {
            diffLines = nil; return
        }
        loadingDiff = true
        diffLines = await CodeGit.diff(repo: repo, file: path)
        loadingDiff = false
    }

    // MARK: Left — changed files

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.t("code.changed")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                if !files.isEmpty {
                    Text("\(files.count)").font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                }
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
        return Button { selected = path } label: {
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
                        if loadingDiff { ProgressView().controlSize(.small) }
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
                    }
                    .padding(Space.m)
                    Divider()
                    if let diff = diffLines, viewMode == .diff {
                        DiffScrollView(lines: diff)
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            Text(fileContents(path))
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Space.m)
                        }
                    }
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

    private func fileContents(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? model.t("code.unreadable")
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
