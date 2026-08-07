//
//  LaunchChecklistView.swift
//  StrategyForge
//
//  A trackable launch plan for a code project: pick a curated template, then tick off the
//  steps. "The boring parts are where launches go wrong" — so this makes the checklist a
//  first-class, persisted object with visible progress, not a dead doc.
//

import SwiftUI

struct LaunchChecklistView: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    private var store: ChecklistStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            if let list = store.checklist(forProject: projectID) {
                header(list)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.l, pinnedViews: [.sectionHeaders]) {
                        ForEach(list.sections) { section in
                            Section {
                                ForEach(section.items) { item in row(list, item) }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                    .padding(Space.m)
                }
            } else {
                emptyState
            }
        }
        .frame(width: 560, height: 640)
        .background(Theme.appBg)
    }

    // MARK: Header + progress

    private func header(_ list: LaunchChecklist) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Label(list.name, systemImage: list.isComplete ? "checkmark.seal.fill" : "checklist")
                    .font(.sfCardTitle)
                    .foregroundStyle(list.isComplete ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.ink))
                Spacer()
                Menu {
                    Button(role: .destructive) { store.delete(list.id) } label: {
                        Label(model.t("checklist.delete"), systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: Space.s) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(list.isComplete ? Theme.success : Theme.coral)
                            .frame(width: max(0, geo.size.width * list.fraction))
                            .animation(.easeOut(duration: 0.25), value: list.fraction)
                    }
                }
                .frame(height: 5)
                Text("\(list.doneItems)/\(list.totalItems)")
                    .font(.sfCaption2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(list.isComplete ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary))
            }
        }
        .padding(Space.m)
        .background(Theme.chromeBg)
    }

    private func sectionHeader(_ section: ChecklistSection) -> some View {
        let done = section.items.filter(\.done).count
        return HStack {
            Text(section.title).font(.sfFieldLabel).foregroundStyle(.tertiary).textCase(.uppercase).tracking(0.6)
            Spacer()
            Text("\(done)/\(section.items.count)").font(.sfFieldLabel).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(.vertical, Space.xs)
        .background(Theme.appBg)
    }

    private func row(_ list: LaunchChecklist, _ item: ChecklistItem) -> some View {
        Button { store.toggle(checklist: list.id, item: item.id) } label: {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.sfBodyM)
                        .foregroundStyle(item.done ? .secondary : .primary)
                        .strikethrough(item.done, color: Theme.ink.opacity(0.3))
                    if !item.hint.isEmpty {
                        Text(item.hint).font(.sfCaption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state (template picker)

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checklist").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text(model.t("checklist.empty.title")).font(.sfCardTitle)
            Text(model.t("checklist.empty.desc")).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            VStack(spacing: Space.s) {
                ForEach(ChecklistTemplateID.allCases, id: \.self) { tpl in
                    Button { start(tpl) } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: tpl.icon).frame(width: 22)
                            Text(ChecklistLibrary.templateName(tpl, es: model.langCode == "es"))
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                        .padding(Space.m)
                        .frame(maxWidth: 360)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.insetBg))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
    }

    private func start(_ tpl: ChecklistTemplateID) {
        store.add(ChecklistLibrary.make(tpl, projectID: projectID, es: model.langCode == "es"))
    }
}
