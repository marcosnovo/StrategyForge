//
//  PreviewPanelView.swift
//  StrategyForge
//
//  The file preview, shown as a sheet from the editor (no longer a permanent
//  column, so the app stays usable at any window size). Shows the launch command
//  and one tab per file that would be written.
//

import SwiftUI

struct FilePreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let config: Configuration

    @State private var selectedFile: String?

    private var launchCommand: String { model.launchCommand(for: config) }
    private var hasRepo: Bool { config.repoPath != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.t("preview.sheetTitle")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.l)

            Divider()
            launchBlock
            Divider()
            previewTabs
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
        // The copy button flashes a banner; as a sheet this view covers the
        // window's banner host, so it carries its own.
        .bannerOverlay()
    }

    // MARK: - Launch command

    private var launchBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.t("preview.launch"), systemImage: "terminal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(launchCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                CopyButton(text: launchCommand,
                           help: model.t("preview.copy.help"),
                           flashKey: "banner.copied")
            }
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .fill(Theme.insetBg)
                    .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                        .strokeBorder(Theme.hairline))
            )
            Text(model.t("preview.launch.caption"))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
    }

    // MARK: - File tabs

    private var previewTabs: some View {
        let diffs = model.previewDiffs(for: config)
        let ids = diffs.map(\.id)
        let effective = (selectedFile.flatMap { ids.contains($0) ? $0 : nil }) ?? diffs.first?.id
        let current = diffs.first { $0.id == effective }

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("preview.diff.header")).font(.sfCardTitle)
                Text(hasRepo
                     ? model.t("preview.diff.caption", (config.repoPath! as NSString).lastPathComponent)
                     : model.t("preview.filesCaptionNoRepo"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.l).padding(.top, Space.m)

            Picker("", selection: Binding(get: { effective }, set: { selectedFile = $0 })) {
                ForEach(diffs) { diff in
                    Text(diff.displayName).tag(Optional(diff.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.l)

            if let current {
                changeBadge(current).padding(.horizontal, Space.l)
            }

            ScrollView {
                if let current {
                    DiffBody(diff: current)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.s)
                }
            }
            .background(Theme.insetBg)
        }
        .onAppear {
            Analytics.log(.diffPreviewed(files: diffs.count,
                                         changed: diffs.filter { $0.change != .unchanged }.count))
        }
    }

    /// A per-file status line: New / Modified (+n −m) / No changes.
    @ViewBuilder
    private func changeBadge(_ diff: FileDiff) -> some View {
        switch diff.change {
        case .created:
            Label(model.t("preview.diff.new"), systemImage: "plus.circle.fill")
                .foregroundStyle(Theme.success)
                .font(.sfCaption2.weight(.semibold))
        case .modified:
            HStack(spacing: 12) {
                Label(model.t("preview.diff.modified"), systemImage: "pencil.circle.fill")
                    .foregroundStyle(Theme.warning)
                Text("+\(diff.added)").foregroundStyle(Theme.success)
                Text("−\(diff.removed)").foregroundStyle(Theme.danger)
            }
            .font(.sfCaption2.weight(.semibold))
            .monospacedDigit()
        case .unchanged:
            Label(model.t("preview.diff.unchanged"), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.sfCaption2.weight(.semibold))
        case .deleted:
            HStack(spacing: 12) {
                Label(model.t("preview.diff.deleted"), systemImage: "trash.circle.fill")
                    .foregroundStyle(Theme.danger)
                Text("−\(diff.removed)").foregroundStyle(Theme.danger)
            }
            .font(.sfCaption2.weight(.semibold))
            .monospacedDigit()
        }
    }
}

/// Renders a file's line-by-line diff: added lines green, removed lines red,
/// context muted. Kept as its own view so the row styling stays simple.
private struct DiffBody: View {
    let diff: FileDiff
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                DiffLineRow(line: line)
            }
        }
    }
}

private struct DiffLineRow: View {
    let line: FileDiffLine
    var body: some View {
        let s = style
        HStack(alignment: .top, spacing: 8) {
            Text(s.prefix)
                .font(.sfCode).foregroundStyle(s.fg)
                .frame(width: 12, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.sfCode)
                .foregroundStyle(line.kind == .context ? Color.primary : s.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, 1)
        .background(s.bg)
    }

    private var style: (prefix: String, fg: Color, bg: Color) {
        switch line.kind {
        case .added:   return ("+", Theme.success, Theme.success.opacity(0.12))
        case .removed: return ("−", Theme.danger, Theme.danger.opacity(0.12))
        case .context: return (" ", .secondary, .clear)
        }
    }
}

private struct SheetHost: View {
    @State private var model = AppModel()
    var body: some View {
        FilePreviewSheet(config: Configuration(name: "Demo", strategy: StrategyLibrary.domainSpecialists(), repoPath: "/Users/me/Projects/app"))
            .environment(model)
            .tint(Theme.accent)
    }
}
#Preview { SheetHost() }
