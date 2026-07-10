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

    /// Chats sorted newest-first, filtered by the search field.
    private var visibleConfigs: [Configuration] {
        let sorted = model.configurations.sorted { $0.recency > $1.recency }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(q)
            || ($0.repoPath ?? "").lowercased().contains(q)
            || model.strategyDisplayName($0.strategy).lowercased().contains(q)
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
                        .padding(.vertical, 3)
                        .tag(config.id)
                        .contextMenu {
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
                    Text(model.t("sidebar.empty"))
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Space.xs)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.appBg)

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
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
        HStack(spacing: Space.s) {
            StrategyThumbnail(strategy: config.strategy)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .help(model.strategyDisplayName(config.strategy))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                        .font(.sfBodyM.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text(config.recency.formatted(.relative(presentation: .named)))
                        .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
                Text(previewLine(config))
                    .font(.sfCaption2)
                    .foregroundStyle(config.repoPath == nil && lastMessage(config) == nil ? Theme.warning : .secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    /// The most recent non-empty message, if any (for the row preview).
    private func lastMessage(_ config: Configuration) -> String? {
        config.transcript.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
    }

    private func previewLine(_ config: Configuration) -> String {
        if let msg = lastMessage(config) {
            return msg.replacingOccurrences(of: "\n", with: " ")
        }
        return config.repoPath.map { ($0 as NSString).lastPathComponent } ?? model.t("chat.noRepo")
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
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m).padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.appBg)
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label(model.t("sidebar.settings"), systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(.bar)
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
        .background(Theme.appBg)
    }
}
