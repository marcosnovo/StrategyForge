//
//  MemoryView.swift
//  StrategyForge
//
//  Manage Coral's cross-project knowledge base: the Learnings (patterns / decisions /
//  mistakes) that ride into future teams' generated CLAUDE.md. Left = a filterable list;
//  right = an editor. Add manually, import from a repo's STATE.md, pin, or delete.
//

import SwiftUI
import AppKit

struct MemoryView: View {
    @Environment(AppModel.self) private var model
    private var store: MemoryStore { .shared }

    @State private var selectedID: Learning.ID?
    @State private var kindFilter: LearningKind?   // nil = all
    /// A focused hygiene review mode (from the "needs attention" bar). nil = normal list.
    @State private var focus: Focus?
    @State private var showAudit = false
    enum Focus: Hashable { case pending, stale, conflicts }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: 340)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .tint(Theme.accent)
        .sheet(isPresented: $showAudit) { auditSheet }
    }

    /// The audit trail — what was learned, approved, edited, forgotten, and when. Keeps the
    /// knowledge base observable and traceable (a wrong memory can be found and rolled back).
    private var auditSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(model.t("memory.audit.title"), systemImage: "clock.arrow.circlepath").font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { showAudit = false }.keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
            Divider()
            if store.auditLog.isEmpty {
                Spacer()
                Text(model.t("memory.audit.empty")).font(.sfCaption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.auditLog) { e in
                            HStack(spacing: Space.s) {
                                Image(systemName: e.action.icon).font(.system(size: 12))
                                    .foregroundStyle(e.action == .forgotten || e.action == .deleted ? Theme.danger : Theme.accent)
                                    .frame(width: 18)
                                Text(model.t(e.action.labelKey)).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.ink)
                                Text(e.title.isEmpty ? model.t("memory.untitled") : e.title)
                                    .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: Space.s)
                                Text(e.at.formatted(date: .abbreviated, time: .shortened))
                                    .font(.sfFieldLabel).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, Space.m).padding(.vertical, 6)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 460)
    }

    private var filtered: [Learning] {
        var base = kindFilter.map { k in store.learnings.filter { $0.kind == k } } ?? store.learnings
        // A hygiene focus narrows the list to just what needs attention.
        switch focus {
        case .pending:   base = base.filter { !$0.reviewed && !$0.pinned }
        case .stale:     base = base.filter { MemoryHygiene.staleness($0, now: Date()) == .stale }
        case .conflicts: base = base.filter { conflictIDs.contains($0.id) }
        case nil:        break
        }
        // Pinned first, then newest — a stable, scannable order.
        return base.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

    /// Ids involved in at least one contradiction (for the conflicts focus + row markers).
    private var conflictIDs: Set<Learning.ID> {
        Set(store.conflicts.flatMap { [$0.a, $0.b] })
    }
    private var staleCount: Int { store.staleLearnings().count }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.t("memory.title")).font(.sfCardTitle)
                Spacer()
                Button { addManual() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help(model.t("memory.add"))
                Button { importStateFile() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain).help(model.t("memory.import"))
                Button { showAudit = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.plain).help(model.t("memory.audit.title"))
            }
            .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.s)
            .background(Theme.chromeBg)

            attentionBar
            filterBar
            Divider()

            if filtered.isEmpty {
                Spacer()
                Text(model.t("memory.empty.desc")).font(.sfCaption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(Space.l)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { learning in row(learning) }
                    }
                    .padding(.horizontal, Space.s).padding(.top, Space.xs)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .translucentColumn()
    }

    /// A compact "needs attention" bar: pending approvals, stale (keep-or-forget), and
    /// contradictions. Each pill toggles a focused review; hidden entirely when all is clean,
    /// so the base stays quiet until there's genuinely something to decide.
    @ViewBuilder private var attentionBar: some View {
        let pending = store.pendingReviewCount
        let stale = staleCount
        let conflicts = store.conflicts.count
        if pending + stale + conflicts > 0 {
            HStack(spacing: Space.xs) {
                if pending > 0 {
                    attentionPill(.pending, "tray.full", "\(pending)", model.t("memory.attn.pending"), Theme.warning)
                }
                if conflicts > 0 {
                    attentionPill(.conflicts, "arrow.triangle.branch", "\(conflicts)", model.t("memory.attn.conflicts"), Theme.danger)
                }
                if stale > 0 {
                    attentionPill(.stale, "wind", "\(stale)", model.t("memory.attn.stale"), Theme.inkDim)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        }
    }

    private func attentionPill(_ f: Focus, _ icon: String, _ count: String, _ label: String, _ tint: Color) -> some View {
        let on = focus == f
        return Button { focus = on ? nil : f; selectedID = nil } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(count).font(.sfCaption2.weight(.semibold)).monospacedDigit()
                Text(label).font(.sfCaption2)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(on ? tint.opacity(0.18) : Theme.insetBg))
            .overlay(Capsule().strokeBorder(on ? tint.opacity(0.6) : .clear, lineWidth: 1))
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var filterBar: some View {
        HStack(spacing: Space.xs) {
            chip(nil, model.t("memory.filter.all"))
            ForEach(LearningKind.allCases, id: \.self) { k in chip(k, model.t(k.displayKey)) }
            Spacer()
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
    }

    private func chip(_ k: LearningKind?, _ label: String) -> some View {
        let on = kindFilter == k
        return Button { kindFilter = k } label: {
            Text(label).font(.sfCaption2.weight(.medium))
                .padding(.horizontal, Space.s).padding(.vertical, 3)
                .background(Capsule().fill(on ? Theme.accentSoft : Color.clear))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(on ? 0.5 : 0.15), lineWidth: 1))
                .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
    }

    private func row(_ learning: Learning) -> some View {
        CoralRow(title: learning.title.isEmpty ? model.t("memory.untitled") : learning.title,
                 subtitle: subtitle(learning),
                 selected: selectedID == learning.id,
                 leading: {
                     Image(systemName: learning.kind.icon).font(.system(size: 14))
                         .foregroundStyle(learning.kind == .mistake ? Theme.danger : Theme.accent)
                         .frame(width: 26, height: 26)
                         .background(Circle().fill(Theme.accentSoft.opacity(0.6)))
                 },
                 trailing: {
                     // Auto-harvested + not yet approved → PENDING: not injected into agents
                     // until a human promotes it. One tap approves (human gatekeeping).
                     if !learning.reviewed && !learning.pinned {
                         Button { store.approve(learning.id) } label: {
                             Label(model.t("memory.approve"), systemImage: "checkmark.seal")
                                 .labelStyle(.titleAndIcon).font(.sfCaption2.weight(.medium))
                                 .foregroundStyle(Theme.warning)
                                 .padding(.horizontal, 6).padding(.vertical, 1)
                                 .background(Capsule().fill(Theme.warning.opacity(0.14)))
                         }
                         .buttonStyle(.plain)
                         .help(model.t("memory.pending.help"))
                     }
                     if conflictIDs.contains(learning.id) {
                         Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(Theme.danger)
                             .help(model.t("memory.attn.conflicts"))
                     }
                     if MemoryHygiene.staleness(learning, now: Date()) == .stale {
                         Image(systemName: "wind").font(.system(size: 10)).foregroundStyle(Theme.inkDim)
                             .help(model.t("memory.staleness.stale"))
                     }
                     if learning.pinned {
                         Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                     }
                 })
            .onTapGesture { selectedID = learning.id }
    }

    private func subtitle(_ l: Learning) -> String {
        var parts = [model.t(l.kind.displayKey)]
        if let scope = l.repoScope, !scope.isEmpty { parts.append((scope as NSString).lastPathComponent) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Detail (editor)

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let binding = binding(for: id) {
            editor(binding).id(id)
        } else {
            ContentUnavailableView {
                Label(model.t("memory.empty.title"), systemImage: "brain")
            } description: {
                Text(model.t("memory.empty.desc"))
            } actions: {
                Button { addManual() } label: {
                    Label(model.t("memory.add"), systemImage: "plus").frame(maxWidth: 320)
                }
                .buttonStyle(.moon).controlSize(.large)
            }
        }
    }

    private func editor(_ learning: Binding<Learning>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Picker("", selection: learning.kind) {
                        ForEach(LearningKind.allCases, id: \.self) { Text(model.t($0.displayKey)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                    Button { store.togglePinned(learning.wrappedValue.id) } label: {
                        Label(model.t(learning.wrappedValue.pinned ? "memory.unpin" : "memory.pin"),
                              systemImage: learning.wrappedValue.pinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button(role: .destructive) {
                        store.delete(learning.wrappedValue.id); selectedID = nil
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                // Contradiction notice: this memory disagrees with another about the same
                // subject. We never auto-merge — the human decides which survives.
                if let other = conflictingPartner(learning.wrappedValue) {
                    hygieneNotice(icon: "arrow.triangle.branch", tint: Theme.danger,
                                  text: model.t("memory.conflict.notice", other.title)) {
                        Button(model.t("memory.conflict.open")) { selectedID = other.id }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                // Staleness notice: old + long unused → keep (mark relevant) or forget.
                if MemoryHygiene.staleness(learning.wrappedValue, now: Date()) == .stale {
                    hygieneNotice(icon: "wind", tint: Theme.inkDim, text: model.t("memory.stale.notice")) {
                        Button(model.t("memory.stale.keep")) { store.markApplied(ids: [learning.wrappedValue.id]) }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button(model.t("memory.stale.forget"), role: .destructive) {
                            store.delete(learning.wrappedValue.id, forgotten: true); selectedID = nil
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }

                field(model.t("memory.field.title")) {
                    TextField(model.t("memory.field.title"), text: learning.title).textFieldStyle(.roundedBorder)
                }
                field(model.t("memory.field.body")) {
                    TextEditor(text: learning.body).font(.sfBodyM).frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                field(model.t("memory.field.tags")) {
                    TextField("swift, ui, …", text: Binding(
                        get: { learning.wrappedValue.tags.joined(separator: ", ") },
                        set: { learning.wrappedValue.tags = $0.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
                        .textFieldStyle(.roundedBorder)
                }
                // Provenance is read-only — a learning always shows where it came from.
                HStack(spacing: Space.s) {
                    Image(systemName: "info.circle").font(.sfCaption2).foregroundStyle(.tertiary)
                    Text(sourceLabel(learning.wrappedValue)).font(.sfCaption2).foregroundStyle(.secondary)
                }
            }
            .padding(Space.xl).frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A calm inset banner used for the conflict / stale prompts — icon + explanation + actions.
    private func hygieneNotice<Actions: View>(icon: String, tint: Color, text: String,
                                              @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon).foregroundStyle(tint).font(.sfCallout)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(text).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s) { actions() }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }

    /// The other learning this one conflicts with (same subject + scope, divergent guidance).
    private func conflictingPartner(_ l: Learning) -> Learning? {
        guard let c = store.conflicts.first(where: { $0.a == l.id || $0.b == l.id }) else { return nil }
        let otherID = (c.a == l.id) ? c.b : c.a
        return store.learning(otherID)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            content()
        }
    }

    private func sourceLabel(_ l: Learning) -> String {
        let origin: String
        switch l.source.origin {
        case .manual: origin = model.t("memory.source.manual")
        case .review: origin = model.t("memory.source.review")
        case .missionReport: origin = model.t("memory.source.mission")
        case .stateFile: origin = model.t("memory.source.state")
        }
        return l.source.detail.isEmpty ? origin : "\(origin) · \(l.source.detail)"
    }

    /// A two-way binding to a stored learning by id — reads live, writes back through
    /// the store (which persists), mirroring LoopStore.binding.
    private func binding(for id: Learning.ID) -> Binding<Learning>? {
        guard store.learnings.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.learnings.first(where: { $0.id == id }) ?? Learning(kind: .pattern, title: "", source: .init(origin: .manual)) },
            set: { store.update($0) })
    }

    // MARK: - Actions

    private func addManual() {
        let new = Learning(kind: kindFilter ?? .pattern, title: "", source: LearningSource(origin: .manual))
        store.add(new)
        selectedID = new.id
    }

    private func importStateFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = model.t("memory.import.message")
        // STATE.md is markdown; allow any file so a user can point at it directly.
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let repo = url.deletingLastPathComponent().path
        let learnings = StateFileParser.learnings(fromStateMd: text, repo: repo)
        guard !learnings.isEmpty else { model.flashFailure(model.t("memory.import.empty")); return }
        for l in learnings { store.add(l) }
        model.flashSuccess(model.t("memory.import.done", learnings.count))
    }
}
