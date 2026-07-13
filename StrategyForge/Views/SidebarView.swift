//
//  SidebarView.swift
//  StrategyForge
//
//  Left pane: brand header + list of saved configurations + Settings.
//  Self-contained (used inside a manual HStack, not a NavigationSplitView).
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSidebar: Bool
    @State private var pendingDelete: Configuration.ID?
    @State private var searchText = ""
    @State private var hoveredID: Configuration.ID?
    /// The chat being renamed (drives the rename dialog) + its editable text.
    @State private var renamingID: Configuration.ID?
    @State private var renameText = ""

    /// Chats sorted newest-first, filtered by the search field.
    private var visibleConfigs: [Configuration] {
        let sorted = model.configurations.sorted { $0.recency > $1.recency }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        // The transcript scan is the costly part (many chats × long histories); only
        // run it once the query is specific enough to be worth it.
        let deep = q.count >= 2
        return sorted.filter {
            $0.name.lowercased().contains(q)
            || ($0.repoPath ?? "").lowercased().contains(q)
            || model.strategyDisplayName($0.strategy).lowercased().contains(q)
            || (deep && $0.transcript.contains { $0.text.lowercased().contains(q) })
        }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            searchField
            Divider()

            List(selection: $model.selectedConfigID) {
                ForEach(visibleConfigs) { config in
                    chatRow(config)
                        .selectedRow(model.selectedConfigID == config.id, cornerRadius: 8)
                        .hoverTint(cornerRadius: 8)
                        .padding(.vertical, Space.xs)
                        .tag(config.id)
                        .contextMenu {
                            Button(model.t("sidebar.rename")) { beginRename(config) }
                            Button(model.t("config.duplicate")) { model.duplicateConfiguration(config.id) }
                            Button(model.t("doc.export")) { model.exportStrategyDocument(config) }
                            if config.repoPath != nil {
                                Button(model.t("config.regenerate")) { model.generate(config) }
                            }
                            Divider()
                            Button(model.t("sidebar.delete"), role: .destructive) {
                                pendingDelete = config.id
                            }
                        }
                }

                if model.configurations.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(model.t("sidebar.empty"))
                            .font(.sfCaption2)
                            .foregroundStyle(.secondary)
                        Button {
                            model.addConfiguration()
                        } label: {
                            Label(model.t("sidebar.empty.cta"), systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.vertical, Space.xs)
                }
            }
            .listStyle(.plain)   // suppress the solid system-accent selection block
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .confirmationDialog(
            model.t("sidebar.deleteTitle"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("sidebar.delete"), role: .destructive) {
                if let id = pendingDelete { model.deleteConfiguration(id) }
                pendingDelete = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(model.t("sidebar.deleteMsg"))
        }
        // Rename a chat inline via a small dialog (also on the row's ✎ / context menu).
        .alert(model.t("sidebar.rename.title"),
               isPresented: Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })) {
            TextField(model.t("chat.untitled"), text: $renameText)
            Button(model.t("common.cancel"), role: .cancel) { renamingID = nil }
            Button(model.t("sidebar.rename")) {
                if let id = renamingID { model.renameConfiguration(id, renameText) }
                renamingID = nil
            }
        }
    }

    /// Rounded search field (reference-style pill) at the top of the chat list.
    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(model.t("sidebar.search"), text: $searchText)
                .textFieldStyle(.plain).font(.sfCaption2)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(Capsule().fill(Theme.insetBg))
        .padding(.horizontal, Space.m).padding(.bottom, Space.s)
    }

    /// A conversation row: a rounded strategy-diagram avatar, the chat title, a
    /// preview of the last message, and the time — like a modern messenger.
    private func chatRow(_ config: Configuration) -> some View {
        let hovering = hoveredID == config.id
        let running = model.runningChatIDs.contains(config.id)
        let selected = model.selectedConfigID == config.id
        return HStack(spacing: Space.s) {
            ChatAvatar(config: config, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                // Title line: name + (on hover) quick rename / delete actions.
                HStack(spacing: 4) {
                    // A coral badge marks a chat that finished / needs a decision while
                    // you were away, so the one needing you is recognizable at a glance.
                    if model.attentionChatIDs.contains(config.id) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                            .help(model.t("sidebar.needsAttention"))
                    }
                    // Marks a chat that continues a summarized one, so the link reads.
                    if config.continuedFrom != nil {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent).help(model.t("chat.continuedFrom"))
                    }
                    Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                        .font(.sfBodyM.weight(model.attentionChatIDs.contains(config.id) ? .bold : .semibold))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Space.xs)
                    if hovering {
                        Button { beginRename(config) } label: {
                            Image(systemName: "pencil").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(model.t("sidebar.rename"))
                        Button { pendingDelete = config.id } label: {
                            Image(systemName: "trash").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(model.t("sidebar.delete"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Meta line: team shape · repo (code cue) · state. When a search
                // matched the conversation body, show that snippet instead so it's
                // clear why the chat surfaced.
                HStack(spacing: Space.xs) {
                    let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
                    if !q.isEmpty, !config.name.lowercased().contains(q),
                       config.transcript.contains(where: { $0.text.lowercased().contains(q) }) {
                        Text(previewLine(config))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    } else {
                        Image(systemName: ChatAvatar.strategyGlyph(config.strategy))
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        Text(model.t(ChatAvatar.shortShapeKey(config.strategy)))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                        if let repo = config.repoPath, !repo.isEmpty {
                            Text("·").font(.sfCaption2).foregroundStyle(.tertiary)
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                            Text((repo as NSString).lastPathComponent)
                                .font(.sfCaption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: Space.xs)
                    // The 3D spinner in the list only earns its place for a chat that's
                    // working while you're NOT looking at it; the selected chat shows
                    // its own activity, so there it's just the time.
                    if running && !selected {
                        WorkingLogo(size: 12)
                    } else {
                        Text(config.recency.formatted(.relative(presentation: .named)))
                            .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { h in
            if h { hoveredID = config.id }
            else if hoveredID == config.id { hoveredID = nil }
        }
    }

    /// Open the rename dialog for a chat, seeded with its current name.
    private func beginRename(_ config: Configuration) {
        renameText = config.name
        renamingID = config.id
    }

    /// The most recent non-empty message, if any (for the row preview).
    private func lastMessage(_ config: Configuration) -> String? {
        config.transcript.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
    }

    private func previewLine(_ config: Configuration) -> String {
        // When a search matched inside the conversation (not the title), show the
        // matching snippet so it's clear WHY this chat surfaced.
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty, !config.name.lowercased().contains(q),
           let hit = config.transcript.first(where: { $0.text.lowercased().contains(q) }) {
            return searchSnippet(around: q, in: hit.text)
        }
        if let msg = lastMessage(config) {
            return msg.replacingOccurrences(of: "\n", with: " ")
        }
        return config.repoPath.map { ($0 as NSString).lastPathComponent } ?? model.t("chat.noRepo")
    }

    /// A short excerpt of `text` centered on the search match, with ellipses.
    private func searchSnippet(around q: String, in text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let r = flat.lowercased().range(of: q) else { return flat }
        let start = flat.index(r.lowerBound, offsetBy: -24, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 40, limitedBy: flat.endIndex) ?? flat.endIndex
        var s = String(flat[start..<end])
        if start != flat.startIndex { s = "…" + s }
        if end != flat.endIndex { s += "…" }
        return s
    }

    private var header: some View {
        // Brand + collapse + new chat now live in the NavRail, so the list header
        // is just its title and the import overflow menu.
        HStack(spacing: Space.s) {
            Text(model.t("sidebar.chats")).font(.sfCardTitle)
            Spacer(minLength: Space.xs)
            Menu {
                Button(model.t("import.repo")) { model.importFromRepo() }
                Button(model.t("doc.import")) { model.importStrategyDocument() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(model.t("import.repo"))
            // Quick "new chat" right where the chats live.
            Button { model.addConfiguration() } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help(model.t("sidebar.new"))
            .accessibilityLabel(model.t("sidebar.new"))
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Theme.titlebarInset).padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .zoomWindowOnDoubleClick()
    }

}

/// The minimized sidebar: a thin full-height rail with expand + new-chat + settings.
struct CollapsedSidebarRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSidebar: Bool

    var body: some View {
        VStack(spacing: Space.l) {
            Button {
                if reduceMotion { showSidebar = true }
                else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help(model.t("sidebar.toggle"))
            .accessibilityLabel(model.t("sidebar.toggle"))

            Button {
                model.addConfiguration()
            } label: {
                Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .help(model.t("sidebar.new"))
            .accessibilityLabel(model.t("sidebar.new"))

            Spacer()

            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .accessibilityLabel(model.t("sidebar.settings"))
        }
        .font(.title3)
        .padding(.vertical, Space.l)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
