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

    private var maps: [SavedMap] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return MapStore.shared.maps }
        return MapStore.shared.maps.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q)
        }
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
                    LazyVStack(spacing: 2) {
                        ForEach(maps) { row($0) }
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
            Button { showImporter = true } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help(model.t("map.pick.repo"))
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
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
