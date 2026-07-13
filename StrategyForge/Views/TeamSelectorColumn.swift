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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedID: SavedTeam.ID?
    @State private var hoveredID: SavedTeam.ID?
    @State private var pendingDelete: SavedTeam.ID?

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        // "Drag your repo and visualize your setup" — drop a folder with .claude/.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.hasDirectoryPath }) else { return false }
            return model.importTeamFromRepo(at: url)
        }
        .confirmationDialog(
            model.t("team.deleteTeam.confirm"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(model.t("team.deleteTeam"), role: .destructive) {
                if let id = pendingDelete { model.deleteTeam(id) }
                pendingDelete = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingDelete = nil }
        }
    }

    private var header: some View {
        HStack {
            Text(model.t("team.title")).font(.sfCardTitle)
            Spacer()
            Menu {
                Button { model.importTeamFromClipboard() } label: {
                    Label(model.t("team.import.paste"), systemImage: "doc.on.clipboard")
                }
                Button { model.importTeamFromFile() } label: {
                    Label(model.t("team.import.file"), systemImage: "arrow.down.doc")
                }
                Button { model.importTeamFromRepoPanel() } label: {
                    Label(model.t("team.import.repo"), systemImage: "folder")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(model.t("team.import"))
            Button {
                model.guardedLeave { selectedID = nil }   // show the create browser
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
        ZStack {
            // Ambient dot-field identity behind the sparse empty column (subtle,
            // stilled under Reduce Motion).
            if !reduceMotion {
                ParticleField(density: 70, reactive: true)
                    .frame(width: 200, height: 200)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
            VStack(spacing: Space.m) {
                Spacer()
                Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(model.t("team.none.title")).font(.sfCardTitle)
                Text(model.t("team.none.desc"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { model.guardedLeave { selectedID = nil } } label: {
                    Label(model.t("team.create"), systemImage: "plus")
                }
                .buttonStyle(.moon)
                Label(model.t("team.dropRepoHint"), systemImage: "arrow.down.doc.fill")
                    .font(.sfCaption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(Space.l)
        }
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
                if hoveredID == team.id {
                    Button {
                        pendingDelete = team.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(model.t("team.deleteTeam"))
                }
            }
            .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .selectedRow(selected, cornerRadius: Theme.innerCorner)
        }
        .buttonStyle(.plain)
        .hoverTint()
        .onHover { hovering in
            if hovering { hoveredID = team.id }
            else if hoveredID == team.id { hoveredID = nil }
        }
        .contextMenu {
            Button {
                model.useTeamInNewChat(team)
            } label: {
                Label(model.t("team.useInChat"), systemImage: "bubble.left.and.bubble.right")
            }
            Button(role: .destructive) { pendingDelete = team.id } label: {
                Label(model.t("team.library.delete"), systemImage: "trash")
            }
        }
    }
}
