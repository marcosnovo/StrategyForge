//
//  CodeSelectorColumn.swift
//  StrategyForge
//
//  The Code section's left column — Código's own list of repo-first sessions, kept SEPARATE from
//  the normal Chats list (founder: "los chats de código que no se mezclen con los normales").
//  Mirrors the Chats sidebar's controls (status · provider · group · sort · search) and adds a
//  REPOSITORY filter + group-by-repo, since a Code list is organised by repo. "+" opens the
//  launcher to start a new one.
//

import SwiftUI

struct CodeSelectorColumn: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    @AppStorage("code.list.groupBy") private var groupBy = "repo"       // repo | date | none
    @AppStorage("code.list.sortBy")  private var sortBy = "recency"     // recency | name | oldest
    @AppStorage("code.list.status")  private var statusFilter = "all"   // all | active
    @AppStorage("code.list.provider") private var providerFilter = "all"
    @AppStorage("code.list.repo")    private var repoFilter = "all"     // all | <repo name>

    /// Every code session (isCode) — the universe this column lists.
    private var codeChats: [Configuration] { model.configurations.filter { $0.isCode } }

    /// Distinct repo names across code chats, for the repo filter menu.
    private var repoNames: [String] {
        var seen = Set<String>(), out: [String] = []
        for c in codeChats {
            let name = c.repoPath.map { ($0 as NSString).lastPathComponent } ?? model.t("chat.group.noRepo")
            if seen.insert(name).inserted { out.append(name) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func repoName(_ c: Configuration) -> String {
        c.repoPath.map { ($0 as NSString).lastPathComponent } ?? model.t("chat.group.noRepo")
    }
    private func isActive(_ c: Configuration) -> Bool {
        model.runningChatIDs.contains(c.id) || model.attentionChatIDs.contains(c.id) || !c.transcript.isEmpty
    }

    private var visible: [Configuration] {
        var list = codeChats
        if statusFilter == "active" { list = list.filter(isActive) }
        if providerFilter != "all" { list = list.filter { $0.provider.rawValue == providerFilter } }
        if repoFilter != "all" { list = list.filter { repoName($0) == repoFilter } }
        switch sortBy {
        case "name":   list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "oldest": list.sort { $0.recency < $1.recency }
        default:       list.sort { $0.recency > $1.recency }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(q) || repoName($0).lowercased().contains(q) }
    }

    private var sections: [(id: String, title: String, items: [Configuration])] {
        switch groupBy {
        case "repo": return grouped(visible) { repoName($0) }
        case "date": return grouped(visible) { dateBucket($0.recency) }
        default:     return []
        }
    }

    private func grouped(_ items: [Configuration], key: (Configuration) -> String)
        -> [(id: String, title: String, items: [Configuration])] {
        var order: [String] = []; var buckets: [String: [Configuration]] = [:]
        for c in items {
            let k = key(c)
            if buckets[k] == nil { buckets[k] = []; order.append(k) }
            buckets[k]?.append(c)
        }
        return order.map { (id: $0, title: $0, items: buckets[$0] ?? []) }
    }

    private func dateBucket(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return model.t("chat.group.today") }
        if cal.isDateInYesterday(date) { return model.t("chat.group.yesterday") }
        if let w = cal.dateInterval(of: .weekOfYear, for: Date()), w.contains(date) { return model.t("chat.group.thisWeek") }
        if let m = cal.dateInterval(of: .month, for: Date()), m.contains(date) { return model.t("chat.group.thisMonth") }
        return model.t("chat.group.older")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            if codeChats.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if groupBy == "none" || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(visible) { row($0) }
                        } else {
                            ForEach(sections, id: \.id) { sec in
                                Section { ForEach(sec.items) { row($0) } } header: { sectionHeader(sec.title) }
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
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Text(model.t("code.list.title")).font(.sfCardTitle)
            Spacer()
            filterMenu
            Button { model.selectedCodeID = nil } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help(model.t("code.list.new"))
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    private var filterMenu: some View {
        Menu {
            Picker(model.t("chat.filter.status"), selection: $statusFilter) {
                Text(model.t("chat.filter.status.all")).tag("all")
                Text(model.t("chat.filter.status.active")).tag("active")
            }
            Picker(model.t("chat.filter.provider"), selection: $providerFilter) {
                Text(model.t("chat.filter.provider.all")).tag("all")
                ForEach(AIProvider.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
            }
            if repoNames.count > 1 {
                Picker(model.t("code.list.repo"), selection: $repoFilter) {
                    Text(model.t("code.list.repo.all")).tag("all")
                    ForEach(repoNames, id: \.self) { Text($0).tag($0) }
                }
            }
            Divider()
            Picker(model.t("chat.groupBy"), selection: $groupBy) {
                Text(model.t("code.list.group.repo")).tag("repo")
                Text(model.t("chat.group.date")).tag("date")
                Text(model.t("chat.group.none")).tag("none")
            }
            Picker(model.t("chat.sortBy"), selection: $sortBy) {
                Text(model.t("chat.sort.recency")).tag("recency")
                Text(model.t("chat.sort.name")).tag("name")
                Text(model.t("chat.sort.oldest")).tag("oldest")
            }
        } label: {
            Image(systemName: (statusFilter != "all" || providerFilter != "all" || repoFilter != "all")
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
            TextField(model.t("code.list.search"), text: $query).textFieldStyle(.plain).font(.sfCaption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.insetBg))
        .padding(.horizontal, Space.m).padding(.top, Space.xs)
    }

    private func row(_ c: Configuration) -> some View {
        let active = model.selectedCodeID == c.id
        let running = model.runningChatIDs.contains(c.id)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12)).foregroundStyle(active ? Theme.coral : Theme.secondaryOnMaterial)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name.isEmpty ? repoName(c) : c.name)
                    .font(.sfBodyM.weight(active ? .semibold : .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(repoName(c)).font(.sfCaption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if running { RunningPulseDotSmall() }
        }
        .padding(.horizontal, Space.s).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            .fill(active ? Theme.coral.opacity(0.09) : .clear))
        .overlay(alignment: .leading) {
            if active { Capsule().fill(Theme.coral).frame(width: 3, height: 20).padding(.leading, 1) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openCodeChat(c.id) }
        .hoverTint(cornerRadius: Theme.rowCorner)
        .help(c.repoPath ?? repoName(c))
        .contextMenu {
            Button(role: .destructive) { model.deleteConfiguration(c.id) } label: {
                Label(model.t("sidebar.delete"), systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 24)).foregroundStyle(.tertiary)
            Text(model.t("code.list.empty")).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.l).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A tiny running pulse dot (teal) for the code list rows.
private struct RunningPulseDotSmall: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(Theme.teal).frame(width: 6, height: 6)
            .opacity(reduceMotion ? 1 : (dim ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}
