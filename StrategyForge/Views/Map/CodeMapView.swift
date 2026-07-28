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
import AppKit
import UniformTypeIdentifiers

struct CodeMapView: View {
    @Environment(AppModel.self) private var model
    @State private var store = CodeMapStore.shared
    @State private var selectedNodeID: String?
    @State private var showImporter = false
    @State private var showHTML = false
    @State private var showGitHub = false

    // GitHub repo picker
    @State private var githubRepos: [GitHubCLI.RepoRef] = []
    @State private var loadingRepos = false
    @State private var repoQuery = ""

    // Search / filter
    @State private var query = ""
    @State private var filterCommunity: Int?

    // graphify explain / path results
    @State private var explainText: String?
    @State private var explaining = false
    @State private var showPath = false
    @State private var pathA = ""
    @State private var pathB = ""
    @State private var pathText: String?
    @State private var pathing = false

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
                store.setLocalRepo(url)
                // If this repo already has a saved map, open it (cached → instant) and let it
                // refresh in the background — so returning from a chat shows an up-to-date map.
                let key = MapStore.key(kind: .local, subtitle: url.path)
                if let saved = MapStore.shared.maps.first(where: { $0.id == key }) {
                    store.openSaved(saved)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                store.setLocalRepo(url)
                selectedNodeID = nil
            }
        }
        .sheet(isPresented: $showHTML) {
            if let html = store.htmlURL { MapHTMLSheet(url: html) }
        }
        .onDisappear { store.stopWatch() }
        .sheet(isPresented: Binding(get: { explainText != nil }, set: { if !$0 { explainText = nil } })) {
            MapTextSheet(title: model.t("map.explain"), text: explainText ?? "")
        }
        .sheet(isPresented: $showPath) { pathSheet }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 15)).foregroundStyle(Theme.coral)
            Text(model.t("map.title")).font(.sfCardTitle)

            repoChip
            githubButton
            recentMenu

            Spacer()

            if store.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text(model.t("map.refreshing")).font(.sfCaption2)
                }
                .foregroundStyle(.secondary)
            }

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

            if let repo = store.repoURL, store.graph != nil {
                Button { model.addConfiguration(repoURL: repo) } label: {
                    Label(model.t("map.chat"), systemImage: "bubble.left.and.bubble.right")
                }
                .controlSize(.small)
                .help(model.t("map.chat.help"))
            }

            if store.graph != nil {
                Button { store.toggleWatch() } label: {
                    Label(model.t("map.watch"), systemImage: store.isWatching ? "eye.fill" : "eye")
                }
                .controlSize(.small)
                .tint(store.isWatching ? Theme.coral : nil)
                .help(model.t("map.watch.help"))
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
        .popover(isPresented: $showGitHub, arrowEdge: .bottom) { githubPicker }
    }

    private var filteredRepos: [GitHubCLI.RepoRef] {
        let q = repoQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return githubRepos }
        return githubRepos.filter { $0.nameWithOwner.localizedCaseInsensitiveContains(q) }
    }

    private var githubPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("map.github.title")).font(.sfCardTitle)
            HStack(spacing: Space.s) {
                TextField(model.t("map.github.placeholder"), text: $store.gitHubInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { startClone() }
                Button(model.t("map.github.map")) { startClone() }
                    .buttonStyle(.moon).controlSize(.small).disabled(!store.canClone)
            }
            Divider()
            if GitHubCLI.isInstalled {
                HStack {
                    Text(model.t("map.github.mine")).font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
                    if !githubRepos.isEmpty { Text("\(githubRepos.count)").font(.sfCaption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if !githubRepos.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                            TextField(model.t("map.search"), text: $repoQuery).textFieldStyle(.plain).font(.sfCaption2).frame(width: 130)
                        }
                    }
                }
                if loadingRepos {
                    HStack { ProgressView().controlSize(.small); Text(model.t("map.github.loading")).font(.sfCaption2).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if githubRepos.isEmpty {
                    Text(model.t("map.github.none")).font(.sfCaption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredRepos) { r in
                                Button {
                                    store.gitHubInput = r.nameWithOwner
                                    startClone()
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: r.isPrivate ? "lock.fill" : "book.closed")
                                            .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(r.name).font(.sfBodyM.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                            Text(r.nameWithOwner).font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 5).padding(.horizontal, 6).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverTint(cornerRadius: Theme.rowCorner)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(model.t("map.github.needGh")).font(.sfCaption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(Space.m)
        .frame(width: 460, height: 460)
        .task { await loadRepos() }
    }

    /// Recently mapped repos, cached — reopening is instant and free (no re-run, no tokens).
    @ViewBuilder
    private var recentMenu: some View {
        if !MapStore.shared.maps.isEmpty {
            Menu {
                ForEach(MapStore.shared.maps) { m in
                    Button {
                        selectedNodeID = nil
                        store.openSaved(m)
                    } label: {
                        Text("\(m.name) · \(m.nodeCount) · \(m.communityCount)")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
                    Text(model.t("map.recent")).font(.sfCaption2.weight(.medium)).lineLimit(1)
                }
                .foregroundStyle(Theme.secondaryOnMaterial)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.insetBg))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(model.t("map.recent"))
        }
    }

    private func loadRepos() async {
        guard GitHubCLI.isInstalled, githubRepos.isEmpty, !loadingRepos else { return }
        loadingRepos = true
        githubRepos = await GitHubCLI.listRepos(limit: 100)
        loadingRepos = false
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
            mapToolbar(graph)
            Divider().opacity(0.3)
            CodeMapGraphView(graph: graph, selectedNodeID: $selectedNodeID, matchIDs: matchIDs(graph))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) { clusterLegend(graph) }
                .padding(Space.m)
            statsBar(graph)
        }
    }

    /// Search box + cluster filter. Matching nodes stay lit in the graph; the rest dim.
    private func mapToolbar(_ graph: CodeGraph) -> some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(model.t("map.search"), text: $query).textFieldStyle(.plain).font(.sfCaption2)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.insetBg))
            .frame(width: 240)

            Menu {
                Button(model.t("map.filter.all")) { filterCommunity = nil }
                Divider()
                ForEach(clusterOptions(graph), id: \.0) { (c, name) in
                    Button { filterCommunity = c } label: {
                        if filterCommunity == c { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 11))
                    Text(filterCommunity.flatMap { clusterName(graph, $0) } ?? model.t("map.filter.all"))
                        .font(.sfCaption2).lineLimit(1)
                }
                .foregroundStyle(filterCommunity == nil ? Theme.secondaryOnMaterial : Theme.coral)
            }
            .menuStyle(.borderlessButton).fixedSize()

            Spacer()
            Text(model.t("map.zoomHint")).font(.sfCaption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
    }

    /// Node ids matching the current search + cluster filter; nil when neither is active.
    private func matchIDs(_ graph: CodeGraph) -> Set<String>? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty || filterCommunity != nil else { return nil }
        return Set(graph.nodes.filter { n in
            (q.isEmpty || n.label.localizedCaseInsensitiveContains(q))
                && (filterCommunity == nil || n.community == filterCommunity)
        }.map { $0.id })
    }

    /// Floating legend of the top clusters (colour + name). Clicking one filters to it —
    /// the legend doubles as the cluster filter and a colour key for the graph.
    private func clusterLegend(_ graph: CodeGraph) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(clusterOptions(graph).prefix(8), id: \.0) { (c, name) in
                Button { filterCommunity = (filterCommunity == c ? nil : c) } label: {
                    HStack(spacing: 5) {
                        Circle().fill(CodeMapGraphView.clusterColor(c)).frame(width: 8, height: 8)
                        Text(name).font(.sfCaption2)
                            .foregroundStyle(filterCommunity == c ? Theme.ink : Theme.secondaryOnMaterial)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .padding(Space.m)
        .frame(maxWidth: 200, alignment: .trailing)
    }

    /// (community index, display name) for the top clusters, for the filter menu.
    private func clusterOptions(_ graph: CodeGraph) -> [(Int, String)] {
        var byComm: [Int: [CodeGraph.Node]] = [:]
        for n in graph.nodes { byComm[n.community, default: []].append(n) }
        return byComm.sorted { $0.value.count > $1.value.count }.prefix(16).map { (c, members) in
            (c, members.compactMap { $0.communityName }.first ?? "Cluster \(c)")
        }
    }
    private func clusterName(_ graph: CodeGraph, _ c: Int) -> String? {
        graph.nodes.first { $0.community == c }?.communityName ?? "Cluster \(c)"
    }

    /// Bottom bar: cluster/node/edge counts, the "showing N of M" cap note, and the
    /// selected node's file:line when one is tapped.
    @ViewBuilder
    private func statsBar(_ graph: CodeGraph) -> some View {
        if let sel = selectedNodeID, let node = graph.nodes.first(where: { $0.id == sel }) {
            selectionBar(node)
        } else {
            HStack(spacing: Space.m) {
                statChip(model.t("map.stat.clusters", graph.communityCount))
                statChip(model.t("map.stat.nodes", graph.nodes.count))
                statChip(model.t("map.stat.edges", graph.edges.count))
                if graph.nodes.count > renderCap {
                    Text(model.t("map.showing", renderCap, graph.nodes.count))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                }
                Text(model.t("map.tapHint")).font(.sfCaption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .background(.bar)
        }
    }

    /// The selected node's identity + actions: open the file, ask an agent, explain it,
    /// or trace a path from it. This is the Map↔code↔chat loop.
    private func selectionBar(_ node: CodeGraph.Node) -> some View {
        HStack(spacing: Space.s) {
            Circle().fill(Theme.coral).frame(width: 7, height: 7)
            Text(node.label).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            if let file = node.file {
                Text(node.line.map { "\(file):\($0)" } ?? file)
                    .font(.sfCode).foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1)
            }
            Spacer()
            if node.file != nil {
                Button { openFile(node) } label: { Label(model.t("map.node.open"), systemImage: "doc.text") }
                    .controlSize(.small)
            }
            Button { explainNode(node) } label: {
                if explaining { ProgressView().controlSize(.mini) }
                else { Label(model.t("map.node.explain"), systemImage: "text.bubble") }
            }
            .controlSize(.small).disabled(explaining)
            Button { askAbout(node) } label: { Label(model.t("map.node.ask"), systemImage: "bubble.left.and.bubble.right") }
                .controlSize(.small)
            Button { pathA = node.label; pathB = ""; pathText = nil; showPath = true } label: {
                Label(model.t("map.node.path"), systemImage: "arrow.triangle.branch")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(.bar)
    }

    // MARK: Node actions

    private func openFile(_ node: CodeGraph.Node) {
        guard let repo = store.repoURL, let file = node.file else { return }
        let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : repo.appendingPathComponent(file)
        NSWorkspace.shared.open(url)
    }

    private func askAbout(_ node: CodeGraph.Node) {
        guard let repo = store.repoURL else { return }
        let loc = node.file.map { f in node.line.map { "\(f):\($0)" } ?? f }
        let where_ = loc.map { " (\($0))" } ?? ""
        let draft = model.t("map.ask.draft", node.label, where_)
        model.addConfiguration(repoURL: repo, draft: draft)
    }

    private func explainNode(_ node: CodeGraph.Node) {
        explaining = true
        Task {
            // Query by id — the canonical node identifier graphify always resolves.
            let text = await store.explain(node.id)
            explainText = text
            explaining = false
        }
    }

    private func runPath() {
        pathing = true
        Task {
            pathText = await store.shortestPath(from: pathA, to: pathB)
            pathing = false
        }
    }

    private var pathSheet: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.t("map.path.title")).font(.sfCardTitle)
            HStack(spacing: Space.s) {
                TextField(model.t("map.path.from"), text: $pathA).textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField(model.t("map.path.to"), text: $pathB).textFieldStyle(.roundedBorder)
                Button(model.t("map.path.find")) { runPath() }
                    .buttonStyle(.moon).disabled(pathA.isEmpty || pathB.isEmpty || pathing)
            }
            if pathing { ProgressView() }
            if let t = pathText {
                ScrollView {
                    Text(t).font(.sfCode).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
            }
            HStack { Spacer(); Button(model.t("common.done")) { showPath = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(Space.l).frame(width: 560)
    }

    private func statChip(_ text: String) -> some View {
        Text(text).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.secondaryOnMaterial)
    }

    // MARK: Empty / status states

    @ViewBuilder
    private var pickRepoState: some View {
        if MapStore.shared.maps.isEmpty {
            ContentUnavailableView {
                Label(model.t("map.empty.title"), systemImage: "circle.hexagongrid")
            } description: {
                Text(model.t("map.empty.desc"))
            } actions: { sourceButtons }
        } else {
            recentsState
        }
    }

    private var sourceButtons: some View {
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

    /// When there are saved maps, the empty state becomes a grid of recents (reopen free)
    /// plus the source buttons — a far more useful landing than a bare prompt.
    private var recentsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Text(model.t("map.recent")).font(.sfDisplay)
                    Spacer()
                    sourceButtons
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Space.m)], spacing: Space.m) {
                    ForEach(MapStore.shared.maps) { m in recentCard(m) }
                }
            }
            .padding(Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recentCard(_ m: SavedMap) -> some View {
        Button {
            selectedNodeID = nil
            store.openSaved(m)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: m.kind == .github ? "cloud" : "folder")
                        .font(.system(size: 12)).foregroundStyle(Theme.coral)
                    Text(m.name).font(.sfBodyM.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                }
                Text(m.subtitle).font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                Text(model.t("map.card.stats", m.nodeCount, m.communityCount))
                    .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
            }
            .padding(Space.m)
            .frame(height: 96, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { MapStore.shared.delete(m) } label: {
                Label(model.t("map.delete"), systemImage: "trash")
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

/// A simple scrollable text sheet — used for graphify's `explain` output.
private struct MapTextSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.sfCardTitle)
                Spacer()
                CopyButton(text: text, help: model.t("chat.copy"), flashKey: "banner.copied")
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(.bar)
            ScrollView {
                Text(text.isEmpty ? "—" : text).font(.sfCode).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.l)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 500)
        .background(Theme.appBg)
    }
}
