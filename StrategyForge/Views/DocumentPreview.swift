//
//  DocumentPreview.swift
//  StrategyForge
//
//  Preview and export files the agent produced — QuickLook for any file type
//  (docs, PDFs, images, code), with reveal-in-Finder, open, and "save a copy"
//  so results from a scratch-folder session can be pulled out.
//

import SwiftUI
import Quartz

/// A native QuickLook preview of a single file, embedded in SwiftUI.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
        }
    }
}

/// A sheet listing the files a turn changed, with a QuickLook preview and export
/// actions. Works for any output — reports, slides, images, code.
struct DocumentPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let files: [String]
    @State private var selection: String

    init(files: [String]) {
        self.files = files
        _selection = State(initialValue: files.first ?? "")
    }

    private var selectedURL: URL? { selection.isEmpty ? nil : URL(fileURLWithPath: selection) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.accent)
                Text(model.t("preview.title")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
            Divider()

            HStack(spacing: 0) {
                if files.count > 1 {
                    fileList
                    Divider()
                }
                Group {
                    if let url = selectedURL {
                        QuickLookPreview(url: url)
                    } else {
                        Text(model.t("preview.none")).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            actionBar
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 640)
    }

    private var fileList: some View {
        List(files, id: \.self, selection: $selection) { path in
            Label((path as NSString).lastPathComponent, systemImage: icon(for: path))
                .lineLimit(1)
                .tag(path)
        }
        .listStyle(.sidebar)
        .frame(width: 240)
    }

    private var actionBar: some View {
        HStack(spacing: Space.s) {
            if let url = selectedURL {
                Text(url.deletingLastPathComponent().path)
                    .font(.sfCaption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let url = selectedURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label(model.t("chat.reveal"), systemImage: "folder")
                }
                Button { NSWorkspace.shared.open(url) } label: {
                    Label(model.t("preview.open"), systemImage: "arrow.up.forward.app")
                }
                Button { saveCopy(of: url) } label: {
                    Label(model.t("preview.save"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.m)
    }

    private func saveCopy(of url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
    }

    private func icon(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return "photo"
        case "pptx", "ppt", "key": return "rectangle.on.rectangle"
        case "docx", "doc", "pages", "rtf": return "doc.text"
        case "xlsx", "xls", "csv", "numbers": return "tablecells"
        case "md", "markdown": return "text.alignleft"
        default: return "doc"
        }
    }
}
