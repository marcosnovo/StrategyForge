//
//  CommandPalette.swift
//  StrategyForge
//
//  A ⌘K Spotlight-style quick-switcher: fuzzy-search across chats and the main
//  actions/sections and jump with the keyboard. For an app whose whole job is
//  switching between agents and chats, this is the fastest way around.
//

import SwiftUI

/// One selectable palette entry: an action to run or a chat to open.
private struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let section: String
    let run: () -> Void
}

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        // Dimmed backdrop that closes on click, with the floating panel on top.
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { close() }
            panel
                .padding(.top, 96)
        }
        .onExitCommand { close() }   // Esc
        .onAppear { searchFocused = true }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            // Search field.
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                TextField(model.t("palette.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.sfBodyM)
                    .focused($searchFocused)
                    .onSubmit(runSelected)
                    .onChange(of: query) { selection = 0 }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s + 2)

            Divider()

            // Results.
            if filtered.isEmpty {
                Text(model.t("palette.empty"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.xl)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                                if idx == 0 || filtered[idx - 1].section != item.section {
                                    Text(item.section.uppercased())
                                        .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.7)
                                        .padding(.horizontal, Space.m)
                                        .padding(.top, idx == 0 ? Space.s : Space.m).padding(.bottom, 2)
                                }
                                row(item, selected: idx == selection)
                                    .id(idx)
                                    .onTapGesture { item.run(); close() }
                            }
                        }
                        .padding(.vertical, Space.xs)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
                }
            }

            Divider()
            HStack {
                Text(model.t("palette.hint")).font(.sfCaption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 14)
        // Arrow-key navigation over the flat result list.
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { runSelected(); return .handled }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: item.icon)
                .font(.system(size: 14)).frame(width: 22)
                .foregroundStyle(selected ? Theme.onAccent : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.sfCallout.weight(.medium))
                    .foregroundStyle(selected ? Theme.onAccent : .primary)
                    .lineLimit(1).truncationMode(.tail)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub).font(.sfCaption2)
                        .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : .secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            .fill(selected ? Theme.accent : .clear))
        .padding(.horizontal, Space.xs)
        .contentShape(Rectangle())
    }

    // MARK: Items

    /// All actions/sections available regardless of the current view.
    private var actionItems: [PaletteItem] {
        let actions = model.t("palette.section.actions")
        func go(_ section: AppModel.NavSection, _ labelKey: String, _ icon: String) -> PaletteItem {
            PaletteItem(id: "go.\(labelKey)", title: model.t("palette.go", model.t(labelKey)),
                        subtitle: nil, icon: icon, section: actions) {
                model.guardedLeave { model.navSection = section }
            }
        }
        return [
            PaletteItem(id: "new.chat", title: model.t("sidebar.new"), subtitle: nil,
                        icon: "square.and.pencil", section: actions) {
                model.guardedLeave { model.navSection = .chats; model.addConfiguration() }
            },
            go(.code, "rail.code", "chevron.left.forwardslash.chevron.right"),
            go(.chats, "sidebar.chats", "bubble.left.and.bubble.right.fill"),
            go(.team, "rail.team", "person.3.sequence.fill"),
            go(.loops, "rail.loops", "arrow.triangle.2.circlepath"),
            go(.skills, "rail.skills", "puzzlepiece.extension.fill"),
            go(.usage, "rail.usage", "gauge.with.dots.needle.bottom.50percent"),
            go(.settings, "sidebar.settings", "gearshape.fill"),
        ]
    }

    /// Every chat, newest first, jumpable by name.
    private var chatItems: [PaletteItem] {
        let chats = model.t("palette.section.chats")
        return model.configurations
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
            .map { config in
                let id = config.id
                let title = config.name.trimmingCharacters(in: .whitespaces)
                return PaletteItem(id: "chat.\(id)",
                                   title: title.isEmpty ? model.t("chat.untitled") : title,
                                   subtitle: model.strategyDisplayName(config.strategy),
                                   icon: "bubble.left.fill", section: chats) {
                    model.guardedLeave { model.navSection = .chats; model.selectedConfigID = id }
                }
            }
    }

    /// Filtered by the query (case-insensitive substring on title + subtitle). With an
    /// empty query, show the actions then a few most-recent chats.
    private var filtered: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return actionItems + Array(chatItems.prefix(6)) }
        func hit(_ i: PaletteItem) -> Bool {
            i.title.lowercased().contains(q) || (i.subtitle?.lowercased().contains(q) ?? false)
        }
        return actionItems.filter(hit) + chatItems.filter(hit)
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selection = (selection + delta + filtered.count) % filtered.count
    }

    private func runSelected() {
        guard filtered.indices.contains(selection) else { return }
        filtered[selection].run()
        close()
    }

    private func close() { isPresented = false }
}
