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

    var body: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: 340)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .tint(Theme.accent)
    }

    private var filtered: [Learning] {
        let base = kindFilter.map { k in store.learnings.filter { $0.kind == k } } ?? store.learnings
        // Pinned first, then newest — a stable, scannable order.
        return base.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

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
            }
            .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.s)
            .background(.bar)

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
