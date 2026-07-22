//
//  LoopSelectorColumn.swift
//  StrategyForge
//
//  The first pane of the Loops section: the list of saved loops. Mirrors
//  TeamSelectorColumn (260pt, material background). Empty state explains what
//  a loop is and offers the create CTA.
//

import SwiftUI

struct LoopSelectorColumn: View {
    @Environment(AppModel.self) private var model
    let store: LoopStore

    @State private var hoveredID: LoopPlan.ID?
    @State private var pendingDelete: LoopPlan.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.loops.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(store.loops) { loopRow($0) }
                    }
                    .padding(Space.m)
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        // Frosted glass column: a translucent material shows the faint aurora as clean
        // neutral vibrancy (matches the chat-list column).
        .translucentColumn()
        .confirmationDialog(
            model.t("loop.delete.confirm"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("loop.delete"), role: .destructive) {
                if let id = pendingDelete { store.delete(id) }
                pendingDelete = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingDelete = nil }
        }
    }

    private var header: some View {
        HStack {
            Text(model.t("rail.loops")).font(.sfCardTitle).foregroundStyle(Theme.ink)
            Spacer()
            Button {
                store.addLoop()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(model.t("loop.create"))
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m).padding(.bottom, Space.s)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(model.t("loop.empty.title")).font(.sfCardTitle)
            Text(model.t("loop.empty.desc"))
                .font(.sfCallout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button {
                store.addLoop()
            } label: {
                Label(model.t("loop.empty.create"), systemImage: "plus")
            }
            .buttonStyle(.moon)
            Spacer()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loopRow(_ loop: LoopPlan) -> some View {
        let selected = store.selectedLoopID == loop.id
        let source = loop.sourceChatName.flatMap { $0.isEmpty ? nil : $0 }
        let subtitle = [model.t(loop.kind.labelKey), source].compactMap { $0 }.joined(separator: " · ")
        return CoralRow(
            title: loop.name.isEmpty ? model.t("loop.untitled") : loop.name,
            subtitle: subtitle,
            selected: selected,
            leading: {
                ZStack {
                    Circle().fill(Theme.accentSoft).frame(width: 28, height: 28)
                    Image(systemName: loop.kind.icon).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            },
            trailing: {
                if hoveredID == loop.id {
                    Button { pendingDelete = loop.id } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless).help(model.t("loop.delete"))
                } else if store.runningLoopIDs.contains(loop.id) {
                    WorkingLogo(size: 12)
                } else if LoopScheduler.isScheduled(loop.id) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 11)).foregroundStyle(Theme.tealText)
                        .help(model.t("loop.schedule.on"))
                } else {
                    Text(model.t("loop.list.turns", loop.maxTurns))
                        .font(.sfCaption2).monospacedDigit().foregroundStyle(.tertiary)
                }
            })
        .onTapGesture {
            store.selectedLoopID = loop.id
            store.save()   // selection is persisted (restored on relaunch)
        }
        .onHover { hovering in
            if hovering { hoveredID = loop.id }
            else if hoveredID == loop.id { hoveredID = nil }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = loop.id
            } label: {
                Label(model.t("loop.delete"), systemImage: "trash")
            }
        }
    }
}
