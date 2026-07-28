//
//  CodeMapView.swift
//  StrategyForge
//
//  The "Map" section: turn the active repo into a code knowledge graph with the
//  open-source `graphify` CLI and render it natively (see CodeMapGraphView). Coral is
//  the vessel — it detects/installs graphify, runs it light-by-default (token-cheap),
//  parses `graph.json`, and draws the clustered map; graphify's own interactive
//  `graph.html` is one click away for full pan/zoom/search. First native slice: no
//  orchestration wiring yet (that's the follow-up), just a usable, beautiful overview.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct CodeMapView: View {
    @Environment(AppModel.self) private var model
    @State private var store = CodeMapStore()
    @State private var selectedNodeID: String?
    @State private var showImporter = false
    @State private var showHTML = false
    @State private var showGitHub = false

    /// Mirrors CodeMapGraphView's node cap — used only for the "showing N of M" note.
    private let renderCap = 240

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.appBg)
        .onAppear {
            store.refreshReadiness()
            if store.repoURL == nil,
               let cfg = model.selectedConfiguration,
               let url = model.repoURL(for: cfg) {
                store.repoURL = url
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                store.repoURL = url
                selectedNodeID = nil
            }
        }
        .sheet(isPresented: $showHTML) {
            if let html = store.htmlURL { MapHTMLSheet(url: html) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 15)).foregroundStyle(Theme.coral)
            Text(model.t("map.title")).font(.sfCardTitle)

            repoChip
            githubButton

            Spacer()

            if store.graph != nil {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text(model.t("map.injected")).font(.sfCaption2.weight(.medium))
                }
                .foregroundStyle(Theme.coral)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.coral.opacity(0.10)))
                .help(model.t("map.injected.help"))
            }

            if store.htmlURL != nil {
                Button { showHTML = true } label: {
                    Label(model.t("map.open.html"), systemImage: "safari")
                }
                .controlSize(.small)
            }

            Button {
                selectedNodeID = nil
                Task { await store.run() }
            } label: {
                Label(store.graph == nil ? model.t("map.run") : model.t("map.rerun"),
                      systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            .buttonStyle(.moon).controlSize(.small)
            .disabled(!store.canRun)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    /// The picked repo as a folder chip; tap to change.
    private var repoChip: some View {
        Button { showImporter = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 11))
                Text(store.repoURL?.lastPathComponent ?? model.t("map.pick.repo"))
                    .font(.sfCaption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(Theme.secondaryOnMaterial)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.insetBg))
        }
        .buttonStyle(.plain)
        .help(store.repoURL?.path ?? model.t("map.pick.repo"))
    }

    /// Map a repo straight from GitHub — no local checkout needed. Coral shallow-clones it
    /// into a managed folder, then maps it.
    private var githubButton: some View {
        Button { showGitHub.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud").font(.system(size: 11))
                Text(model.t("map.github")).font(.sfCaption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(Theme.secondaryOnMaterial)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.insetBg))
        }
        .buttonStyle(.plain)
        .help(model.t("map.github.title"))
        .popover(isPresented: $showGitHub, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(model.t("map.github.title")).font(.sfBodyM.weight(.semibold))
                TextField(model.t("map.github.placeholder"), text: $store.gitHubInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { startClone() }
                HStack {
                    Spacer()
                    Button(model.t("map.github.map")) { startClone() }
                        .buttonStyle(.moon).controlSize(.small).disabled(!store.canClone)
                }
            }
            .padding(Space.m).frame(width: 360)
        }
    }

    private func startClone() {
        showGitHub = false
        selectedNodeID = nil
        Task { await store.cloneAndMap() }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .needsPython:
            needsPythonState
        case .preparing:
            busyState(model.t("map.preparing"))
        case .cloning:
            busyState(model.t("map.cloning"))
        case .running:
            busyState(model.t("map.running"))
        case .failed(let msg):
            failedState(msg)
        case .idle, .done:
            if let graph = store.graph, !graph.isEmpty {
                graphState(graph)
            } else if store.repoURL == nil {
                pickRepoState
            } else {
                readyState
            }
        }
    }

    private func graphState(_ graph: CodeGraph) -> some View {
        VStack(spacing: 0) {
            CodeMapGraphView(graph: graph, selectedNodeID: $selectedNodeID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Space.m)
            statsBar(graph)
        }
    }

    /// Bottom bar: cluster/node/edge counts, the "showing N of M" cap note, and the
    /// selected node's file:line when one is tapped.
    private func statsBar(_ graph: CodeGraph) -> some View {
        HStack(spacing: Space.m) {
            if let sel = selectedNodeID, let node = graph.nodes.first(where: { $0.id == sel }) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.coral).frame(width: 7, height: 7)
                    Text(node.label).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if let kind = node.kind {
                        Text(kind).font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                    }
                    if let file = node.file {
                        Text(node.line.map { "\(file):\($0)" } ?? file)
                            .font(.sfCode).foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1)
                    }
                }
            } else {
                statChip(model.t("map.stat.clusters", graph.communityCount))
                statChip(model.t("map.stat.nodes", graph.nodes.count))
                statChip(model.t("map.stat.edges", graph.edges.count))
                if graph.nodes.count > renderCap {
                    Text(model.t("map.showing", renderCap, graph.nodes.count))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(.bar)
    }

    private func statChip(_ text: String) -> some View {
        Text(text).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.secondaryOnMaterial)
    }

    // MARK: Empty / status states

    private var pickRepoState: some View {
        ContentUnavailableView {
            Label(model.t("map.empty.title"), systemImage: "circle.hexagongrid")
        } description: {
            Text(model.t("map.empty.desc"))
        } actions: {
            HStack(spacing: Space.s) {
                Button { showImporter = true } label: {
                    Label(model.t("map.pick.repo"), systemImage: "folder")
                }
                .buttonStyle(.moon).controlSize(.large)
                Button { showGitHub = true } label: {
                    Label(model.t("map.github"), systemImage: "cloud")
                }
                .controlSize(.large)
            }
        }
    }

    private var readyState: some View {
        ContentUnavailableView {
            Label(model.t("map.ready.title"), systemImage: "point.3.filled.connected.trianglepath.dotted")
        } description: {
            Text(model.t("map.ready.desc"))
        } actions: {
            Button { Task { await store.run() } } label: {
                Label(model.t("map.run"), systemImage: "sparkles").frame(maxWidth: 320)
            }
            .buttonStyle(.moon).controlSize(.large).disabled(!store.canRun)
        }
    }

    /// Coral installs graphify itself; the only thing it can't provide is Apple's
    /// Command Line Tools (python3). Shown only when that base is missing.
    private var needsPythonState: some View {
        ContentUnavailableView {
            Label(model.t("map.needsPython.title"), systemImage: "wrench.and.screwdriver")
        } description: {
            VStack(spacing: Space.s) {
                Text(model.t("map.needsPython.desc"))
                Text("xcode-select --install").font(.sfCode).foregroundStyle(Theme.secondaryOnMaterial)
                    .textSelection(.enabled)
            }
        } actions: {
            HStack {
                Button { store.installCommandLineTools() } label: {
                    Label(model.t("map.installCLT"), systemImage: "arrow.down.circle").frame(maxWidth: 260)
                }
                .buttonStyle(.moon).controlSize(.large)
                CopyButton(text: "xcode-select --install", help: model.t("chat.copy"), flashKey: "banner.copied")
            }
        }
    }

    private func busyState(_ label: String) -> some View {
        VStack(spacing: Space.m) {
            ProgressView().controlSize(.large)
            Text(label).font(.sfBodyM).foregroundStyle(Theme.secondaryOnMaterial)
            if let repo = store.repoURL { Text(repo.lastPathComponent).font(.sfCaption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedState(_ msg: String) -> some View {
        ContentUnavailableView {
            Label(model.t("map.failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg).font(.sfCode).foregroundStyle(Theme.secondaryOnMaterial)
                .textSelection(.enabled).lineLimit(6)
        } actions: {
            Button { Task { await store.run() } } label: {
                Label(model.t("map.retry"), systemImage: "arrow.clockwise").frame(maxWidth: 240)
            }
            .buttonStyle(.moon).controlSize(.large).disabled(!store.canRun)
        }
    }
}

/// graphify's interactive `graph.html` in a sheet — full pan/zoom/search, loaded from
/// the on-disk file so its bundled assets resolve.
private struct MapHTMLSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.t("map.html.title")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(.bar)
            MapFileWebView(url: url)
        }
        .frame(minWidth: 760, idealWidth: 1000, minHeight: 520, idealHeight: 720)
        .background(Theme.appBg)
    }
}

private struct MapFileWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
