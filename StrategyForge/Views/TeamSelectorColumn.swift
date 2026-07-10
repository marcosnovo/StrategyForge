//
//  TeamSelectorColumn.swift
//  StrategyForge
//
//  The first pane of the Team section: pick which team to work on. Lists the user's
//  teams (each configuration holds a team) plus their saved presets, with an empty
//  state + "create a new team" CTA when there are none. Selecting one drives the
//  wide strategy browser + configuration panes to its right.
//

import SwiftUI

struct TeamSelectorColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedID: Configuration.ID?

    private var teams: [Configuration] {
        model.configurations.sorted { $0.recency > $1.recency }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if teams.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(teams) { teamRow($0) }
                        if !model.savedTeams.isEmpty { presetsSection }
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
                model.addConfiguration()   // TODO: create-team CTA flow (adapt preset / blank)
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
            Image(systemName: "person.3")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(model.t("team.none.title")).font(.sfCardTitle)
            Text(model.t("team.none.desc"))
                .font(.sfCallout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button {
                model.addConfiguration()   // TODO: create-team CTA flow
            } label: {
                Label(model.t("team.create"), systemImage: "plus")
            }
            .buttonStyle(.moon)
            Spacer()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func teamRow(_ config: Configuration) -> some View {
        let selected = selectedID == config.id
        return Button {
            selectedID = config.id
        } label: {
            HStack(spacing: Space.s) {
                StrategyThumbnail(strategy: config.strategy)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                        .font(.sfCallout.weight(.medium)).lineLimit(1)
                    Text(model.t("team.members.count", config.strategy.roles.count))
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
    }

    @ViewBuilder
    private var presetsSection: some View {
        Text(model.t("team.library.yours"))
            .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            .padding(.top, Space.s)
        ForEach(model.savedTeams) { team in
            Button {
                if let id = selectedID { model.applyTeam(team, to: id) }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 34)
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
            }
            .buttonStyle(.plain)
            .disabled(selectedID == nil)
            .contextMenu {
                Button(role: .destructive) { model.deleteTeam(team.id) } label: {
                    Label(model.t("team.library.delete"), systemImage: "trash")
                }
            }
        }
    }
}
