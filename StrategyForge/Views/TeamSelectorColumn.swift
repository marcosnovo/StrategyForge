//
//  TeamSelectorColumn.swift
//  StrategyForge
//
//  The first pane of the Team section: your library of reusable teams (SavedTeam),
//  independent of chats. Empty state + "create a team" CTA when there are none.
//  Selecting a team opens it in the editor; the CTA/"+" deselects to show the
//  strategy browser (create surface).
//

import SwiftUI

struct TeamSelectorColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedID: SavedTeam.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.savedTeams.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(model.savedTeams) { teamRow($0) }
                    }
                    .padding(Space.m)
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Text(model.t("team.title")).font(.sfCardTitle)
            Spacer()
            Button {
                selectedID = nil   // show the create browser
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(model.t("team.create"))
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m).padding(.bottom, Space.s)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            Spacer()
            Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(.secondary)
            Text(model.t("team.none.title")).font(.sfCardTitle)
            Text(model.t("team.none.desc"))
                .font(.sfCallout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { selectedID = nil } label: {
                Label(model.t("team.create"), systemImage: "plus")
            }
            .buttonStyle(.moon)
            Spacer()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func teamRow(_ team: SavedTeam) -> some View {
        let selected = selectedID == team.id
        return Button {
            selectedID = team.id
        } label: {
            HStack(spacing: Space.s) {
                StrategyThumbnail(strategy: team.strategy)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(team.name).font(.sfCallout.weight(.medium)).lineLimit(1)
                    Text(model.t("team.members.count", team.strategy.roles.count))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { model.deleteTeam(team.id) } label: {
                Label(model.t("team.library.delete"), systemImage: "trash")
            }
        }
    }
}
