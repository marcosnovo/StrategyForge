//
//  SkillsView.swift
//  StrategyForge
//
//  The Skills marketplace (v1): Discover (curated + paste a GitHub ref) and Manage
//  (installed skills, view the SKILL.md, remove). Install writes files only — a
//  trust note flags any skill that can run code, since Coral isn't sandboxed.
//

import SwiftUI
import AppKit

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    private var store: SkillStore { .shared }

    enum Tab: String, CaseIterable { case top, discover, installed }
    @State private var tab: Tab = .top
    @State private var selected: AgentSkill?
    @State private var pasteRef = ""
    @State private var fetching = false
    @State private var errorText: String?
    // The Top tab list (community-by-stars, or the official catalog fallback) now lives on
    // SkillStore.shared so it survives this view being recreated when you switch sections —
    // it loads once and is reused instead of re-fetching every time.
    /// A fetched, not-yet-installed skill awaiting the trust/confirm sheet.
    @State private var pending: AgentSkill?
    @State private var installing = false
    /// Discover/Installed filters.
    @State private var query = ""
    @State private var kindFilter: KindFilter = .all

    enum KindFilter: String, CaseIterable {
        case all, knowledge, code
        func matches(_ s: AgentSkill) -> Bool {
            switch self {
            case .all: return true
            case .knowledge: return s.kind == .knowledge
            case .code: return s.kind == .code
            }
        }
    }

    private var projectRepo: URL? {
        model.selectedConfiguration?.repoPath.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: 340)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .tint(Theme.accent)
        .task(id: tab) {
            store.scan(projectRepo: projectRepo)
            if tab == .top { await store.loadTopIfNeeded() }
        }
    }

    private func formatStars(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("skills.title")).font(.sfCardTitle)
                Text(model.t("skills.subtitle")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: $tab) {
                    Text(model.t("skills.tab.top")).tag(Tab.top)
                    Text(model.t("skills.tab.discover")).tag(Tab.discover)
                    Text(model.t("skills.tab.installed")).tag(Tab.installed)
                }
                .labelsHidden().pickerStyle(.segmented).tint(Theme.coral).padding(.top, Space.xs)
            }
            .padding(Space.m).background(.regularMaterial).zoomWindowOnDoubleClick()
            Divider()
            filterBar
            Divider()
            ScrollView {
                switch tab {
                case .top: topList
                case .discover: discoverList
                case .installed: installedList
                }
            }
            .background(Theme.appBg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Search field + knowledge/code type filter — shared by both tabs.
    private var filterBar: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(model.t("skills.search"), text: $query)
                    .textFieldStyle(.plain).font(.sfCaption2)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Space.s).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.insetBg))
            Picker("", selection: $kindFilter) {
                Text(model.t("skills.kind.all")).tag(KindFilter.all)
                Text(model.t("skills.kind.knowledge")).tag(KindFilter.knowledge)
                Text(model.t("skills.kind.code")).tag(KindFilter.code)
            }
            .labelsHidden().pickerStyle(.segmented).tint(Theme.coral)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s).background(.regularMaterial)
    }

    /// A curated entry's coarse type — code if its known slug ships scripts, else
    /// knowledge. (The document/artifacts skills are all code-bearing.)
    private func matchesFilters(_ c: CuratedSkill) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let text = "\(c.name) \(c.description) \(c.category)".lowercased()
        if !q.isEmpty && !text.contains(q) { return false }
        if kindFilter == .knowledge { return false }   // curated set is code-bearing today
        return true
    }
    private func matchesFilters(_ s: AgentSkill) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let text = "\(s.name) \(s.description)".lowercased()
        if !q.isEmpty && !text.contains(q) { return false }
        return kindFilter.matches(s)
    }

    /// The live official Anthropic skills catalog — always current, with an
    /// "installed" mark on any you already have.
    private var topList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t(store.topCommunity ? "skills.top.community" : "skills.top.note"))
                .font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if store.isLoadingTop {
                HStack(spacing: Space.s) { WorkingLogo(size: 14)
                    Text(model.t("skills.top.loading")).font(.sfCaption2).foregroundStyle(.secondary) }
                    .padding(.vertical, Space.s)
            }
            if let e = store.topError, tab == .top {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.sfCaption2)
                    .foregroundStyle(Theme.warningText).fixedSize(horizontal: false, vertical: true)
            }
            let shown = store.topSkills.filter(matchesFilters)
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in curatedRow(c, rank: i + 1) }
        }
        .padding(Space.s)
    }

    private var discoverList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Paste any GitHub ref (owner/repo[@ref][#path]).
            HStack(spacing: Space.xs) {
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(model.t("skills.discover.paste"), text: $pasteRef)
                    .textFieldStyle(.plain).font(.sfCode).onSubmit { install(ref: pasteRef) }
                if fetching { WorkingLogo(size: 14) }
            }
            .padding(.horizontal, Space.s).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.insetBg))
            if let e = errorText {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.sfCaption2)
                    .foregroundStyle(Theme.warningText).fixedSize(horizontal: false, vertical: true)
            }
            let shown = store.allCurated.filter(matchesFilters)
            if shown.isEmpty && kindFilter == .knowledge {
                Text(model.t("skills.discover.noKnowledge")).font(.sfCaption2)
                    .foregroundStyle(.tertiary).padding(.vertical, Space.s)
            } else if shown.isEmpty {
                Text(model.t("skills.noResults")).font(.sfCaption2)
                    .foregroundStyle(.tertiary).padding(.vertical, Space.s)
            }
            // Grouped by category, alphabetized, so it's easy to scan what's on offer.
            let groups = Dictionary(grouping: shown, by: { $0.category })
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            ForEach(groups, id: \.key) { category, items in
                Text(category).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
                    .padding(.leading, Space.xs).padding(.top, Space.xs)
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                    curatedRow(c)
                }
            }
        }
        .padding(Space.s)
    }

    private func curatedRow(_ c: CuratedSkill, rank: Int? = nil) -> some View {
        let installed = store.isInstalled(slug: c.slug)
        return Button { install(curated: c) } label: {
            HStack(spacing: Space.s) {
                if let rank {
                    Text("\(rank)").font(.sfCaption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                }
                // Neutral (coral discipline): a coral icon on all 13 rows diluted the accent
                // into wallpaper. The row's colour now comes only where it MEANS something —
                // the teal verified seal + the green "installed" mark.
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 13))
                    .foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(c.name).font(.sfCallout.weight(.medium)).lineLimit(1)
                        if c.verified {
                            Image(systemName: "checkmark.seal.fill").scaledFont(9).foregroundStyle(Theme.tealText)
                        }
                    }
                    Text(c.description).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let stars = c.stars {
                    Label(formatStars(stars), systemImage: "star.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                if installed {
                    Label(model.t("skills.installedMark"), systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly).font(.system(size: 13)).foregroundStyle(Theme.success)
                        .help(model.t("skills.installedMark"))
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .selectedRow(pending?.slug == c.slug, cornerRadius: 8)
        }
        .buttonStyle(.plain).hoverTint(cornerRadius: 8).disabled(fetching)
    }

    @ViewBuilder
    private var installedList: some View {
        if store.installed.isEmpty {
            ContentUnavailableView {
                Label(model.t("skills.installed.empty"), systemImage: "puzzlepiece.extension")
            } description: { Text(model.t("skills.installed.emptyDesc")) }
                .padding(.top, Space.xl)
        } else {
            let filtered = store.installed.filter(matchesFilters)
            let personal = filtered.filter { if case .personal = $0.scope { return true } else { return false } }
            let project = filtered.filter { if case .project = $0.scope { return true } else { return false } }
            VStack(alignment: .leading, spacing: Space.s) {
                if filtered.isEmpty {
                    Text(model.t("skills.noResults")).font(.sfCaption2)
                        .foregroundStyle(.tertiary).padding(.vertical, Space.s)
                }
                if !personal.isEmpty { section(model.t("skills.section.personal"), personal) }
                if !project.isEmpty { section(model.t("skills.section.project"), project) }
            }
            .padding(Space.s)
        }
    }

    private func section(_ title: String, _ skills: [AgentSkill]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6).padding(.leading, Space.xs)
            ForEach(skills) { skill in installedRow(skill) }
        }
    }

    private func installedRow(_ skill: AgentSkill) -> some View {
        Button { selected = skill; pending = nil } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 12))
                    .foregroundStyle(selected?.id == skill.id ? Theme.accent : .secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name).font(.sfCallout.weight(.medium)).lineLimit(1)
                    Text(skill.description).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                kindTag(skill.kind)
                if skill.canRunCode {
                    Image(systemName: "exclamationmark.shield.fill").font(.system(size: 10))
                        .foregroundStyle(Theme.warningText).help(model.t("skills.trust.title"))
                }
            }
            .padding(.vertical, 5).padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .selectedRow(selected?.id == skill.id, cornerRadius: 8)
        }
        .buttonStyle(.plain).hoverTint(cornerRadius: 8)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if fetching && pending == nil {
            VStack(spacing: Space.s) { WorkingLogo(size: 22); Text(model.t("skills.fetching")).font(.sfCaption2).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let p = pending {
            previewDetail(p)
        } else if let s = selected, store.installed.contains(where: { $0.id == s.id }) {
            installedDetail(s)
        } else {
            ContentUnavailableView {
                Label(model.t("skills.detail.title"), systemImage: "puzzlepiece.extension")
            } description: { Text(model.t("skills.detail.desc")) }
        }
    }

    /// Detail for an INSTALLED skill: badges, use-in-team, reveal/remove, playbook.
    private func installedDetail(_ s: AgentSkill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.sfDisplay)
                        Text(s.description).font(.sfCallout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                HStack(spacing: Space.s) {
                    scopeBadge(s.scope)
                    kindTag(s.kind)
                    if s.canRunCode {
                        Label(model.t("skills.trust.badge"), systemImage: "exclamationmark.shield.fill")
                            .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.warningText)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.warning.opacity(0.14)))
                    }
                    Spacer()
                    useInTeamMenu(s)
                    if let p = s.localPath {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([p]) } label: {
                            Label(model.t("skills.reveal"), systemImage: "arrow.up.forward.app")
                        }.controlSize(.small)
                    }
                    if s.coralManaged {
                        Button(role: .destructive) { try? store.uninstall(s); selected = nil } label: {
                            Label(model.t("skills.remove"), systemImage: "trash")
                        }.controlSize(.small)
                    }
                }
                teamsUsing(s)
                Divider()
                MarkdownView(text: s.body.isEmpty ? s.description : s.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.xl).frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Detail for a DISCOVER preview (not yet installed) — shown in the right pane
    /// instead of a modal: header, source, trust note, scope + Install, playbook.
    private func previewDetail(_ p: AgentSkill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.sfDisplay)
                        Text(p.description).font(.sfCallout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if case .github(let o, let r, _, _) = p.source {
                            Text("\(o)/\(r) · \(model.t("skills.source.community"))")
                                .font(.sfCaption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    kindTag(p.kind)
                }
                if p.canRunCode {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.warningText)
                        Text(model.t("skills.trust.body")).font(.sfCaption2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.warning.opacity(0.10)))
                }
                // Install controls: scope + action, inline (no modal).
                HStack(spacing: Space.m) {
                    Picker(model.t("skills.scope.label"), selection: $confirmScope) {
                        Text(model.t("skills.scope.personal")).tag(AgentSkill.Scope.personal)
                        if let repo = projectRepo { Text(repo.lastPathComponent).tag(AgentSkill.Scope.project(repo)) }
                    }
                    .fixedSize()
                    Spacer()
                    Button(model.t("common.cancel")) { pending = nil }
                    Button(model.t("skills.confirm.install")) {
                        let preview = p, scope = confirmScope
                        installing = true
                        Task {
                            do {
                                _ = try await store.install(preview, into: scope)
                                model.flashSuccess(model.t("skills.installedOk", preview.name))
                                pending = nil; tab = .installed
                                selected = store.installed.first { $0.slug == preview.slug }
                            } catch { model.flashFailure(model.t("skills.installFailed")) }
                            installing = false
                        }
                    }
                    .buttonStyle(.moon).controlSize(.small).disabled(installing)
                }
                Divider()
                MarkdownView(text: p.body.isEmpty ? p.description : p.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.xl).frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Use in a team" — a menu of saved teams; toggling attaches/detaches the skill.
    /// Attached skills are copied into the repo's .claude/skills when the team is generated.
    @ViewBuilder
    private func useInTeamMenu(_ s: AgentSkill) -> some View {
        if model.savedTeams.isEmpty {
            EmptyView()
        } else {
            Menu {
                ForEach(model.savedTeams) { team in
                    Button {
                        model.toggleSkill(s.slug, inTeam: team.id)
                    } label: {
                        if model.team(team.id, hasSkill: s.slug) {
                            Label(team.name, systemImage: "checkmark")
                        } else {
                            Text(team.name)
                        }
                    }
                }
            } label: {
                Label(model.t("skills.useInTeam"), systemImage: "person.3.sequence.fill")
            }
            .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
        }
    }

    /// Teams currently using this skill — shown as a caption under the header.
    @ViewBuilder
    private func teamsUsing(_ s: AgentSkill) -> some View {
        let names = model.savedTeams.filter { $0.strategy.skills.contains(s.slug) }.map(\.name)
        if !names.isEmpty {
            Label(model.t("skills.usedInTeams", names.joined(separator: ", ")), systemImage: "person.3.sequence.fill")
                .font(.sfCaption2).foregroundStyle(.secondary)   // informational, not live state → neutral
        }
    }

    /// Small pill showing the coarse type — knowledge (playbook) vs code (ships scripts).
    private func kindTag(_ kind: AgentSkill.Kind) -> some View {
        let (label, icon, tint): (String, String, Color) = kind == .code
            ? (model.t("skills.kind.code"), "terminal", Theme.accent)
            : (model.t("skills.kind.knowledge"), "book", Theme.teal)
        return Label(label, systemImage: icon)
            .scaledFont(9, weight: .medium).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func scopeBadge(_ scope: AgentSkill.Scope) -> some View {
        let (label, icon): (String, String) = {
            switch scope {
            case .personal: return (model.t("skills.scope.personal"), "person")
            case .project(let r): return (r.lastPathComponent, "folder")
            }
        }()
        return Label(label, systemImage: icon)
            .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.insetBg))
    }

    // MARK: - Install (fetch → trust/confirm sheet → write)

    private func install(curated c: CuratedSkill) {
        errorText = nil; fetching = true; selected = nil
        Task { do { pending = try await store.preview(c) } catch { errorText = error.localizedDescription }; fetching = false }
    }
    private func install(ref: String) {
        guard !ref.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorText = nil; fetching = true; selected = nil
        Task { do { pending = try await store.preview(githubRef: ref) } catch { errorText = error.localizedDescription }; fetching = false }
    }

    @State private var confirmScope: AgentSkill.Scope = .personal
}
