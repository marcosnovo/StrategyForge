//
//  ArtifactPanel.swift
//  StrategyForge
//
//  "Artifacts": substantial code / HTML / SVG blocks an assistant reply produced,
//  opened in a focused viewer beside the chat (Rendered + Source tabs) instead of
//  scrolling a giant fenced block inline. Detection is a plain fenced-block scan.
//

import SwiftUI
import WebKit

/// One extractable artifact from a message: a fenced code block worth viewing on
/// its own. Renderable when it's HTML/SVG we can show live.
struct Artifact: Identifiable, Hashable {
    let id = UUID()
    var language: String
    var code: String
    var lineCount: Int { code.reduce(1) { $1 == "\n" ? $0 + 1 : $0 } }
    var isRenderable: Bool {
        ["html", "svg", "xml"].contains(language.lowercased())
    }
    /// A short label for the picker (language + size).
    var label: String {
        let lang = language.isEmpty ? "code" : language
        return "\(lang) · \(lineCount)"
    }

    /// Fenced blocks in `text` big/rich enough to be worth a dedicated viewer:
    /// ≥ 14 lines, or any HTML/SVG regardless of size.
    static func extract(from text: String) -> [Artifact] {
        var out: [Artifact] = []
        let lines = text.components(separatedBy: "\n")
        var inFence = false
        var lang = ""
        var buffer: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    let code = buffer.joined(separator: "\n")
                    let art = Artifact(language: lang, code: code)
                    if art.isRenderable || art.lineCount >= 14 { out.append(art) }
                    inFence = false; lang = ""; buffer = []
                } else {
                    inFence = true
                    lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else if inFence {
                buffer.append(line)
            }
        }
        return out
    }
}

/// The artifact viewer sheet: pick a block, toggle Rendered/Source, copy.
struct ArtifactSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let artifacts: [Artifact]

    @State private var selectedID: Artifact.ID?
    @State private var showSource = false

    private var current: Artifact? {
        artifacts.first { $0.id == selectedID } ?? artifacts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Text(model.t("artifact.title")).font(.sfCardTitle)
                if artifacts.count > 1 {
                    Picker("", selection: Binding(get: { current?.id },
                                                  set: { selectedID = $0 })) {
                        ForEach(artifacts) { a in Text(a.label).tag(Optional(a.id)) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                Spacer()
                if let a = current, a.isRenderable {
                    Picker("", selection: $showSource) {
                        Text(model.t("artifact.rendered")).tag(false)
                        Text(model.t("artifact.source")).tag(true)
                    }
                    .pickerStyle(.segmented).tint(Theme.coral).fixedSize()
                }
                if let a = current {
                    CopyButton(text: a.code, help: model.t("chat.copy"), flashKey: "banner.copied")
                }
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background {
                Rectangle().fill(Theme.chromeBg)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zIndex(1)

            if let a = current {
                if a.isRenderable && !showSource {
                    ArtifactWebView(html: a.language.lowercased() == "svg"
                                    ? "<html><body style=\"margin:0;display:flex;justify-content:center\">\(a.code)</body></html>"
                                    : a.code)
                        .padding(Space.m)
                } else {
                    ScrollView {
                        Text(a.code).font(.sfCode).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Space.l)
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg))
                    .padding(Space.m)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 460, idealHeight: 600)
        // Neutral, opaque sheet base so source code / rendered artifacts sit on a
        // readable surface (the .bar header stays frosted).
        .background(Theme.appBg)
    }
}

/// A minimal WKWebView host to render an artifact's HTML/SVG live.
private struct ArtifactWebView: NSViewRepresentable {
    let html: String
    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.setValue(false, forKey: "drawsBackground")
        return v
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }
}
