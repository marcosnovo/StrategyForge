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

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()

            List(selection: $model.selectedConfigID) {
                ForEach(model.configurations.sorted { $0.recency > $1.recency }) { config in
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

    /// A conversation row: the strategy as a small diagram thumbnail (hover to read
    /// its name), then the chat title (primary) and the project it acts on.
    private func chatRow(_ config: Configuration) -> some View {
        HStack(spacing: Space.s) {
            StrategyThumbnail(strategy: config.strategy)
                .frame(width: 52, height: 34)
                .help(model.strategyDisplayName(config.strategy))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                        .font(.sfBodyM.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    if config.updatedAt != .distantPast {
                        Text(config.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Text(config.repoPath.map { ($0 as NSString).lastPathComponent } ?? model.t("chat.noRepo"))
                    .font(.sfCaption2)
                    .foregroundStyle(config.repoPath == nil ? Theme.warning : .secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.title3)
                (Text("Strategy").foregroundStyle(.primary)
                 + Text("Forge").foregroundStyle(Theme.accent))
                    .font(.sfDisplay)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: Space.xs)
                // Secondary: import flows tucked into an overflow menu.
                Menu {
                    Button(model.t("import.repo")) { model.importFromRepo() }
                    Button(model.t("doc.import")) { model.importStrategyDocument() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                // Collapse the sidebar into the minimized rail.
                Button {
                    if reduceMotion { showSidebar = false }
                    else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = false } }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help(model.t("sidebar.toggle"))
                .accessibilityLabel(model.t("sidebar.toggle"))
            }
            // Primary: new chat.
            Button {
                model.addConfiguration()
            } label: {
                Label(model.t("sidebar.new"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .help(model.t("sidebar.new"))
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m)
        .padding(.bottom, Space.m)
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
