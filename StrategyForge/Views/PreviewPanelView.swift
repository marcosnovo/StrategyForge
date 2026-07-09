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
    @State private var didCopy = false

    private var files: [GeneratedFile] { model.previewFiles(for: config) }
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
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(launchCommand, forType: .string)
                    model.flashSuccess(model.t("banner.copied"))
                    flashCopied()
                } label: {
                    Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(didCopy ? Color.green : Theme.accent)
                }
                .buttonStyle(.borderless)
                .help(model.t("preview.copy.help"))
                .accessibilityLabel(model.t("preview.copy.help"))
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
        let generated = files
        let ids = generated.map(\.id)
        let effective = (selectedFile.flatMap { ids.contains($0) ? $0 : nil }) ?? generated.first?.id

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("preview.filesHeader")).font(.sfCardTitle)
                Text(hasRepo
                     ? model.t("preview.filesCaption", (config.repoPath! as NSString).lastPathComponent)
                     : model.t("preview.filesCaptionNoRepo"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.l).padding(.top, Space.m)

            Picker("", selection: Binding(get: { effective }, set: { selectedFile = $0 })) {
                ForEach(generated) { file in
                    Text(file.displayName).tag(Optional(file.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.l)

            let current = generated.first { $0.id == effective }
            ScrollView {
                Text(current?.contents ?? "")
                    .font(.sfCode)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.l)
            }
            .background(Theme.insetBg)
        }
    }

    private func flashCopied() {
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
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
