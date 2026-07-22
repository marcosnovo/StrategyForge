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
    /// Regenerate asked from the context menu while agent files already exist on disk —
    /// holds the chat id + the conflicting paths for the same confirmation the editor uses.
    @State private var pendingRegenerate: Configuration.ID?
    @State private var regenerateConflicts: [String] = []
    @State private var searchText = ""
    /// Debounced copy of `searchText` used for the COSTLY filter (full transcript scan
    /// across every chat). Typing updates `searchText` instantly (responsive field) but
    /// the scan only re-runs ~300ms after the user stops — not on every keystroke.
    @State private var debouncedQuery = ""
    @State private var searchDebounce: Task<Void, Never>?
    /// Deep-search results, computed ONCE per debounced query (off the main actor)
    /// instead of re-scanning every transcript on every body invalidation: chat id →
    /// the first transcript message matching `debouncedQuery` (kept whole so the row
    /// can show its "why it surfaced" snippet). Nil when no deep query is active.
    @State private var deepMatches: [Configuration.ID: String]?
    @State private var hoveredID: Configuration.ID?
    /// Per-chat token bumped when a chat finishes (running → not running), which fires
    /// a discreet sphere-resolve on its thumbnail — the celebration moved here from the
    /// center of the screen.
    @State private var finishToken: [Configuration.ID: Int] = [:]
    /// The chat being renamed (drives the rename dialog) + its editable text.
    @State private var renamingID: Configuration.ID?
    @State private var renameText = ""

    /// Chats sorted newest-first, filtered by the search field.
    private var visibleConfigs: [Configuration] {
        let sorted = model.configurations.sorted { $0.recency > $1.recency }
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        // The transcript scan is the costly part (many chats × long histories); it
        // runs once per debounced query in the search task, so here — inside a body
        // computed property that re-evaluates on every invalidation — the deep match
        // is just a dictionary lookup.
        return sorted.filter {
            $0.name.lowercased().contains(q)
            || ($0.repoPath ?? "").lowercased().contains(q)
            || model.strategyDisplayName($0.strategy).lowercased().contains(q)
            || deepMatches?[$0.id] != nil
        }
    }

    /// True only when the chat list actually spans more than one AI provider — then a
    /// per-row provider dot informs; otherwise it's noise (and a coral Claude dot looks
    /// like a false "needs you" alert), so it's hidden.
    private var mixedProviders: Bool {
        Set(model.configurations.map { $0.provider }).count > 1
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            searchField
            Divider()

            // A plain ScrollView + LazyVStack, NOT List(selection:) — the macOS List
            // selection highlight paints a solid system-accent block that .listStyle
            // can't suppress, which buried our soft selection treatment. Selection is
            // driven by tap so our .selectedRow (tint + hairline + bar) is the only cue.
            // A plain ScrollView + LazyVStack, NOT List(selection:) — a real List paints a
            // flat GRAY system-selection block (verified on screen) that buries our soft coral
            // selection, and its hover is invisible. Selection is driven by tap so our
            // `.selectedRow` (coral wash + hairline + spine) and `.hoverTint` are the cues.
            ScrollView {
                LazyVStack(spacing: 5) {   // room to breathe — the list was too cramped
                    ForEach(visibleConfigs) { config in
                        chatRow(config)
                            .selectedRow(model.selectedConfigID == config.id, cornerRadius: Theme.rowCorner)
                            .hoverTint(cornerRadius: Theme.rowCorner)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedConfigID = config.id }
                            // VoiceOver: one focusable button per chat, carrying its selected
                            // state and a live "running / loop running" value.
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(model.selectedConfigID == config.id
                                                    ? [.isButton, .isSelected] : .isButton)
                            .accessibilityLabel(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                            .accessibilityValue(rowAccessibilityValue(config))
                            .contextMenu {
                                Button(model.t("sidebar.rename")) { beginRename(config) }
                                Button(model.t("config.duplicate")) { model.duplicateConfiguration(config.id) }
                                Button(model.t("doc.export")) { model.exportStrategyDocument(config) }
                                if config.repoPath != nil {
                                    Button(model.t("config.regenerate")) {
                                        // Same overwrite gate as the editor's Generate button —
                                        // a context-menu click must not silently clobber agent
                                        // files the user edited by hand.
                                        let conflicts = model.overwriteConflicts(for: config)
                                        if conflicts.isEmpty {
                                            model.generate(config)
                                        } else {
                                            regenerateConflicts = conflicts
                                            pendingRegenerate = config.id
                                        }
                                    }
                                }
                                Divider()
                                Button(model.t("sidebar.delete"), role: .destructive) {
                                    pendingDelete = config.id
                                }
                            }
                    }
                    if model.configurations.isEmpty {
                        // The native, premium empty state (used consistently app-wide now).
                        ContentUnavailableView {
                            Label(model.t("sidebar.empty.cta"), systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text(model.t("sidebar.empty"))
                        } actions: {
                            Button { model.addConfiguration() } label: {
                                Label(model.t("sidebar.new"), systemImage: "square.and.pencil")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, Space.xl)
                    }
                }
                .padding(.horizontal, Space.s).padding(.top, Space.xs)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Translucent, but tinted to the chat/panel color (Theme.columnBg) rather than
        // the aurora — matching the nav rail so the two left columns read as the same
        // neutral surface as the chat window and activity panel, just glassy.
        .translucentColumn()
        // A chat that just stopped running → fire its thumbnail's sphere-resolve.
        .onChange(of: model.runningChatIDs) { wasRunning, nowRunning in
            for id in wasRunning.subtracting(nowRunning) { finishToken[id, default: 0] += 1 }
        }
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
        // Overwrite confirmation for context-menu Regenerate (mirrors the editor's).
        .confirmationDialog(
            model.t("preview.overwriteTitle"),
            isPresented: Binding(get: { pendingRegenerate != nil }, set: { if !$0 { pendingRegenerate = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("preview.overwrite"), role: .destructive) {
                if let id = pendingRegenerate,
                   let config = model.configurations.first(where: { $0.id == id }) {
                    model.generate(config)
                }
                pendingRegenerate = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingRegenerate = nil }
        } message: {
            Text(model.t("preview.overwriteMsg", regenerateConflicts.joined(separator: "\n")))
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
                Button { searchText = ""; debouncedQuery = ""; deepMatches = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        // Debounce the costly transcript filter: short queries apply immediately (cheap,
        // name/repo/team only), longer ones wait ~300ms after the last keystroke, then
        // scan every chat's history ONCE off the main actor and publish the match set —
        // body invalidations while the query is active only do dictionary lookups.
        .onChange(of: searchText) { _, new in scheduleDeepScan(for: new) }
        // Re-run an active deep search when background hydration lands: right after
        // launch the first scan may have snapshot placeholder (empty) transcripts,
        // and without this the stale miss would persist until the query changed.
        .onChange(of: model.transcriptHydrationGeneration) { _, _ in
            guard searchText.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
            scheduleDeepScan(for: searchText)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        // Clean neutral inset well (not translucent glass over the aurora) so the
        // search text reads without color bleed. Rounded to match innerCorner.
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .fill(Theme.insetBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, Space.m).padding(.bottom, Space.s)
    }

    /// Debounce the costly transcript scan for one query, then publish the match set.
    private func scheduleDeepScan(for new: String) {
        searchDebounce?.cancel()
        if new.trimmingCharacters(in: .whitespaces).count < 2 {
            debouncedQuery = new; deepMatches = nil; return
        }
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let q = new.trimmingCharacters(in: .whitespaces).lowercased()
            // Snapshot on the main actor (value types — a cheap CoW copy, no
            // string work), scan in a detached task so long histories never
            // stall the UI, then publish both halves of the result together.
            let snapshot = model.configurations.map { ($0.id, $0.transcript) }
            let matches = await Task.detached(priority: .userInitiated) { () -> [Configuration.ID: String] in
                var out: [Configuration.ID: String] = [:]
                for (id, transcript) in snapshot {
                    if let hit = transcript.first(where: { $0.text.lowercased().contains(q) }) {
                        out[id] = hit.text
                    }
                }
                return out
            }.value
            if !Task.isCancelled { deepMatches = matches; debouncedQuery = new }
        }
    }

    /// A conversation row: a rounded strategy-diagram avatar, the chat title, a
    /// preview of the last message, and the time — like a modern messenger.
    private func chatRow(_ config: Configuration) -> some View {
        let hovering = hoveredID == config.id
        let running = model.runningChatIDs.contains(config.id)
        // A loop born from this chat is running "over" it (in the Loops section) — surface
        // it here so the chat and its loop stay visibly connected.
        let loopRunning = LoopStore.shared.isLoopRunning(forChat: config.id)
        let selected = model.selectedConfigID == config.id
        return HStack(spacing: Space.s) {
            ChatAvatar(config: config, size: 38, running: running,
                       attention: model.attentionChatIDs.contains(config.id),
                       showProvider: mixedProviders)
                .overlay { WowSphereResolve(token: finishToken[config.id] ?? 0).frame(width: 52, height: 52) }
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
                        Image(systemName: "arrow.turn.down.right").scaledFont(9, weight: .semibold)
                            .foregroundStyle(Theme.accent).help(model.t("chat.continuedFrom"))
                    }
                    Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                        .font(.sfBodyM.weight(model.attentionChatIDs.contains(config.id) ? .bold : .semibold))
                        .foregroundStyle(Theme.ink)
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
                // Meta line, driven by what you need to KNOW at a glance, in priority
                // order: a search hit → why it surfaced; needs-you → the actionable
                // state (coral); running → live (teal); otherwise the last message
                // (messenger style), prefixed with a code cue when bound to a repo.
                HStack(spacing: Space.xs) {
                    let q = debouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
                    let searchHit = !q.isEmpty && !config.name.lowercased().contains(q)
                        && deepMatches?[config.id] != nil
                    if searchHit {
                        Text(previewLine(config))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    } else if model.attentionChatIDs.contains(config.id) {
                        Text(model.t("sidebar.needsAttention"))
                            .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
                            .lineLimit(1).truncationMode(.tail)
                    } else if running {
                        Text(model.t("sidebar.working"))
                            .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.tealText)
                            .lineLimit(1).truncationMode(.tail)
                    } else if loopRunning {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .scaledFont(9, weight: .semibold).foregroundStyle(Theme.accent)
                        Text(model.t("sidebar.loopRunning"))
                            .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
                            .lineLimit(1).truncationMode(.tail)
                    } else {
                        if let repo = config.repoPath, !repo.isEmpty {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .scaledFont(8, weight: .semibold).foregroundStyle(.tertiary)
                        }
                        Text(subtitleLine(config))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: Space.xs)
                    // The 3D spinner in the list only earns its place for a chat that's
                    // working while you're NOT looking at it; the selected chat shows
                    // its own activity, so there it's just the time.
                    if running && !selected {
                        WorkingLogo(size: 12)
                    } else if loopRunning {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                            .help(model.t("sidebar.loopRunning"))
                    } else {
                        Text(config.recency.formatted(.relative(presentation: .named)))
                            .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 4)   // taller rows read premium; the list was cramped
        .contentShape(Rectangle())
        .onHover { h in
            if h { hoveredID = config.id }
            else if hoveredID == config.id { hoveredID = nil }
        }
    }

    /// VoiceOver value for a chat row: the live state a sighted user reads from the
    /// teal "Working" text / spinner or the loop glyph, spoken instead.
    private func rowAccessibilityValue(_ config: Configuration) -> String {
        if model.attentionChatIDs.contains(config.id) { return model.t("sidebar.needsAttention") }
        if model.runningChatIDs.contains(config.id) { return model.t("sidebar.working") }
        if LoopStore.shared.isLoopRunning(forChat: config.id) { return model.t("sidebar.loopRunning") }
        return ""
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

    /// The idle-state subtitle: the last message (messenger style), or — for a chat
    /// with no conversation yet — its repo name, else the team-shape name.
    private func subtitleLine(_ config: Configuration) -> String {
        if let msg = lastMessage(config) {
            return msg.replacingOccurrences(of: "\n", with: " ")
        }
        if let repo = config.repoPath, !repo.isEmpty {
            return (repo as NSString).lastPathComponent
        }
        return model.t(ChatAvatar.shortShapeKey(config.strategy))
    }

    private func previewLine(_ config: Configuration) -> String {
        // When a search matched inside the conversation (not the title), show the
        // matching snippet so it's clear WHY this chat surfaced. The hit text comes
        // from the debounce task's cached scan — no per-row transcript walk here.
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty, !config.name.lowercased().contains(q),
           let hit = deepMatches?[config.id] {
            return searchSnippet(around: q, in: hit)
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
            Text(model.t("sidebar.chats")).font(.sfCardTitle).foregroundStyle(Theme.ink)
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
        .padding(.top, model.titlebarTopInset).padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No opaque fill — the frosted column reads through the header (Aetheris).
        .zoomWindowOnDoubleClick()
    }

}
