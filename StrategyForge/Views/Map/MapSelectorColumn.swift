//
//  MapSelectorColumn.swift
//  StrategyForge
//
//  The Map section's left column: a list of every code map you've generated, so you can
//  see them all and switch between them in one click (mirrors the Loops/Team selector
//  columns). Selecting one opens it from cache — instant and free — into the shared
//  CodeMapStore that the main graph view renders. A "+" adds a new map from a local folder.
//

import SwiftUI
import UniformTypeIdentifiers

struct MapSelectorColumn: View {
    @Environment(AppModel.self) private var model
    private var store: CodeMapStore { .shared }
    @State private var query = ""
    @State private var showImporter = false
    // Group / sort / filter the map list, mirroring the Chats sidebar — so a big list of
    // repositories stays ordered. Persisted, like the chat list's preferences.
    @AppStorage("map.groupBy") private var groupBy = "date"       // date | kind | none
    @AppStorage("map.sortBy")  private var sortBy = "recency"     // recency | name | oldest
    @AppStorage("map.kind")    private var kindFilter = "all"     // all | local | github

    /// The maps to show: dedupe → kind filter → sort → search. (Grouping happens in `sections`.)
    private var visibleMaps: [SavedMap] {
        var list = Self.deduped(MapStore.shared.maps)
        if kindFilter != "all" { list = list.filter { $0.kind.rawValue == kindFilter } }
        switch sortBy {
        case "name":   list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "oldest": list.sort { $0.createdAt < $1.createdAt }
        default:       list.sort { $0.updatedAt > $1.updatedAt }   // recency
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q)
        }
    }

    /// Collapse repeats of the SAME repo — e.g. a map built both from a GitHub clone (kind
    /// .github) and from its local path (kind .local), or a clone whose path drifted into a new
    /// id — keeping the most recently updated. Purely a display concern (the store is untouched).
    static func deduped(_ maps: [SavedMap]) -> [SavedMap] {
        var best: [String: SavedMap] = [:]
        var order: [String] = []
        for m in maps {
            let key = identity(m)
            if let existing = best[key] {
                if m.updatedAt > existing.updatedAt { best[key] = m }
            } else {
                best[key] = m; order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// A repo's identity independent of kind/path: its basename, lowercased. GitHub uses the
    /// "owner/repo" tail; local uses the repo folder name.
    private static func identity(_ m: SavedMap) -> String {
        let base = m.kind == .github
            ? (m.subtitle as NSString).lastPathComponent
            : ((m.repoPath.map { ($0 as NSString).lastPathComponent }) ?? m.name)
        return base.lowercased()
    }

    /// The list split into titled sections per the group-by choice (empty when grouping is off).
    private var sections: [(id: String, title: String, items: [SavedMap])] {
        switch groupBy {
        case "kind":
            return grouped(visibleMaps) { $0.kind == .github ? model.t("map.group.github") : model.t("map.group.local") }
        case "date":
            return grouped(visibleMaps) { dateBucket($0.updatedAt) }
        default:
            return []   // "none" → flat list
        }
    }

    private func grouped(_ items: [SavedMap], key: (SavedMap) -> String)
        -> [(id: String, title: String, items: [SavedMap])] {
        var order: [String] = []
        var buckets: [String: [SavedMap]] = [:]
        for m in items {
            let k = key(m)
            if buckets[k] == nil { buckets[k] = []; order.append(k) }
            buckets[k]?.append(m)
        }
        return order.map { (id: $0, title: $0, items: buckets[$0] ?? []) }
    }

    private func dateBucket(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return model.t("chat.group.today") }
        if cal.isDateInYesterday(date) { return model.t("chat.group.yesterday") }
        if let week = cal.dateInterval(of: .weekOfYear, for: Date()), week.contains(date) { return model.t("chat.group.thisWeek") }
        if let month = cal.dateInterval(of: .month, for: Date()), month.contains(date) { return model.t("chat.group.thisMonth") }
        return model.t("chat.group.older")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if MapStore.shared.maps.isEmpty {
                emptyState
            } else {
                searchField
                ScrollView {
                    LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if groupBy == "none" || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(visibleMaps) { row($0) }
                        } else {
                            ForEach(sections, id: \.id) { sec in
                                Section {
                                    ForEach(sec.items) { row($0) }
                                } header: {
                                    sectionHeader(sec.title)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 260)
        .background(Theme.appBg)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                store.setLocalRepo(url)
                Task { await store.run() }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(model.t("map.column.title")).font(.sfCardTitle)
            Spacer()
            filterMenu
            Button { showImporter = true } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help(model.t("map.pick.repo"))
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    /// Filter (by type) + group-by + sort, mirroring the Chats list's menu. The icon fills
    /// when a non-default filter is active so it reads as "on".
    private var filterMenu: some View {
        Menu {
            Picker(model.t("map.filter.kind"), selection: $kindFilter) {
                Text(model.t("map.filter.kind.all")).tag("all")
                Text(model.t("map.group.local")).tag("local")
                Text(model.t("map.group.github")).tag("github")
            }
            Divider()
            Picker(model.t("chat.groupBy"), selection: $groupBy) {
                Text(model.t("chat.group.date")).tag("date")
                Text(model.t("map.group.kind")).tag("kind")
                Text(model.t("chat.group.none")).tag("none")
            }
            Picker(model.t("chat.sortBy"), selection: $sortBy) {
                Text(model.t("chat.sort.recency")).tag("recency")
                Text(model.t("chat.sort.name")).tag("name")
                Text(model.t("chat.sort.oldest")).tag("oldest")
            }
        } label: {
            Image(systemName: kindFilter != "all"
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(model.t("chat.filter.help"))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.sfFieldLabel).foregroundStyle(.tertiary).textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, Space.s).padding(.top, Space.s).padding(.bottom, 2)
        .background(Theme.appBg)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(model.t("map.search"), text: $query).textFieldStyle(.plain).font(.sfCaption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.insetBg))
        .padding(.horizontal, Space.m).padding(.top, Space.xs)
    }

    private func row(_ m: SavedMap) -> some View {
        let active = store.currentMapID == m.id
        let onDisk = m.repoPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return HStack(spacing: 8) {
            Image(systemName: m.kind == .github ? "cloud" : "folder")
                .font(.system(size: 12)).foregroundStyle(active ? Theme.coral : Theme.secondaryOnMaterial)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.sfBodyM.weight(active ? .semibold : .medium))
                    .foregroundStyle(Theme.ink).lineLimit(1)
                Text(model.t("map.card.stats", m.nodeCount, m.communityCount))
                    .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
                Text(model.t("map.updated", Self.relative(m.updatedAt)))
                    .font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            // Rebuild this map on demand (needs the repo on disk).
            if onDisk {
                Button {
                    store.openSaved(m)
                    Task { await store.run() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(store.phase == .running || store.phase == .preparing)
                .help(model.t("map.rebuild"))
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            .fill(active ? Theme.coral.opacity(0.09) : .clear))
        .overlay(alignment: .leading) {
            if active { Capsule().fill(Theme.coral).frame(width: 3, height: 20).padding(.leading, 1) }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.openSaved(m) }
        .hoverTint(cornerRadius: Theme.rowCorner)
        .help(m.subtitle)
        .contextMenu {
            Button(role: .destructive) {
                MapStore.shared.delete(m)
            } label: { Label(model.t("map.delete"), systemImage: "trash") }
        }
    }

    /// Short relative time, e.g. "2h", "3d" — for the map's last update.
    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    private var emptyState: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "circle.hexagongrid").font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(model.t("map.column.empty")).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showImporter = true } label: {
                Label(model.t("map.pick.repo"), systemImage: "folder")
            }
            .controlSize(.small)
        }
        .padding(Space.l).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
