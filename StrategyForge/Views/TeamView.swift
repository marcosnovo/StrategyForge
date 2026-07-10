//
//  TeamView.swift
//  StrategyForge
//
//  The Team editor: a visual canvas of a SAVED TEAM's agents (orchestrator +
//  subagents as interactive cards) with an inline detail panel to configure the
//  selected agent, plus add/remove. Teams are independent, reusable presets — a
//  chat can then use one; they are NOT chats.
//

import SwiftUI

struct TeamView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var team: SavedTeam

    @State private var selectedRoleID: AgentRole.ID?
    @State private var confirmDeleteTeam = false
    @State private var pendingDeleteRole: AgentRole.ID?

    private var strategy: Strategy { team.strategy }

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            detailPanel
                .frame(width: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .onAppear {
            if selectedRoleID == nil || !strategy.roles.contains(where: { $0.id == selectedRoleID }) {
                selectedRoleID = strategy.orchestrator?.id ?? strategy.roles.first?.id
            }
        }
        .onChange(of: team.id) {
            selectedRoleID = strategy.orchestrator?.id ?? strategy.roles.first?.id
        }
        .confirmationDialog(model.t("team.deleteTeam.confirm"), isPresented: $confirmDeleteTeam, titleVisibility: .visible) {
            Button(model.t("team.deleteTeam"), role: .destructive) { model.deleteTeam(team.id) }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(model.t("team.deleteAgent.confirm"),
                            isPresented: Binding(get: { pendingDeleteRole != nil },
                                                 set: { if !$0 { pendingDeleteRole = nil } }),
                            titleVisibility: .visible) {
            Button(model.t("team.delete"), role: .destructive) {
                if let rid = pendingDeleteRole {
                    model.deleteRole(rid, fromTeam: team.id)
                    selectedRoleID = strategy.orchestrator?.id
                }
                pendingDeleteRole = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingDeleteRole = nil }
        }
    }

    // MARK: - Canvas (left)

    private var canvas: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if let orch = strategy.orchestrator {
                        sectionLabel("team.orchestrator.section", systemImage: "crown.fill")
                        agentCard(orch)
                    }

                    if !strategy.subagentRoles.isEmpty {
                        HStack(spacing: Space.s) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            Text(model.t("team.delegatesTo", strategy.subagentRoles.count))
                                .font(.sfCaption2).foregroundStyle(.secondary)
                        }
                        .padding(.leading, Space.s)
                    }

                    HStack {
                        sectionLabel("team.members.section", systemImage: "person.2.fill")
                        Spacer()
                        Text(model.t("team.members.count", strategy.subagentRoles.count))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.m)],
                              alignment: .leading, spacing: Space.m) {
                        ForEach(strategy.subagentRoles) { role in
                            agentCard(role)
                        }
                        addCard
                    }

                    connectionNote
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(model.t("team.name"), text: $team.name)
                    .textFieldStyle(.plain)
                    .font(.sfDisplay)
                Text(model.strategyDisplayName(strategy))
                    .font(.sfCallout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            costPill
            Menu {
                Button { model.copyTeamShareText(team) } label: {
                    Label(model.t("team.share.copy"), systemImage: "square.on.square")
                }
                Button { model.exportTeamDocument(team) } label: {
                    Label(model.t("team.share.export"), systemImage: "arrow.up.doc")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDeleteTeam = true
                } label: {
                    Label(model.t("team.deleteTeam"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button {
                if model.save() { model.flashSuccess(model.t("banner.saved")) }
            } label: {
                Label(model.t("editor.save"), systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.moon)
            .controlSize(.large)
        }
        .padding(Space.l)
    }

    private var costPill: some View {
        let cost = CostEstimator.estimate(strategy)
        let color: Color
        switch cost.tier {
        case .low: color = Theme.success
        case .medium: color = Theme.warning
        case .high: color = Theme.danger
        }
        return HStack(spacing: 5) {
            Image(systemName: "bolt.fill").font(.system(size: 9))
            Text(model.t("cost.perRun", String(format: "$%.2f", cost.perRun)))
                .font(.sfCaption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private func sectionLabel(_ key: String, systemImage: String) -> some View {
        Label(model.t(key), systemImage: systemImage)
            .font(.sfFieldLabel).foregroundStyle(.secondary).tracking(0.6)
    }

    private var connectionNote: some View {
        Label(model.t("team.flow.note"), systemImage: "arrow.triangle.branch")
            .font(.sfCaption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Agent card

    private func agentCard(_ role: AgentRole) -> some View {
        let selected = selectedRoleID == role.id
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedRoleID = role.id }
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    ZStack {
                        Circle().fill(role.role.tint.opacity(0.16)).frame(width: 34, height: 34)
                        Image(systemName: role.role.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(role.role.tint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(role.name).font(.sfCallout.weight(.semibold)).lineLimit(1)
                        Text(model.roleKindName(role.role).uppercased())
                            .font(.system(size: 8, weight: .bold)).tracking(0.4)
                            .foregroundStyle(role.role.tint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(role.role.tint.opacity(0.16)))
                    }
                    Spacer(minLength: 0)
                    if role.count > 1 {
                        Text("×\(role.count)")
                            .font(.sfCaption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.hairline))
                    }
                }
                HStack(spacing: 4) {
                    ProviderLogo(provider: role.provider, size: 12, templateTint: role.provider.tint)
                    if role.provider == .claude {
                        Image(systemName: role.model.tierIcon).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(role.modelDisplayName).font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? role.role.tint.opacity(0.08) : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? role.role.tint : Theme.hairline,
                              lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(role.description)
    }

    private var addCard: some View {
        Button {
            if let id = model.addRole(toTeam: team.id) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedRoleID = id }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text(model.t("team.add")).font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(Theme.accentSoft.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t("team.add.help"))
    }

    // MARK: - Detail panel (right)

    @ViewBuilder
    private var detailPanel: some View {
        if let roleID = selectedRoleID,
           let role = strategy.roles.first(where: { $0.id == roleID }) {
            let issues = strategy.validate().filter { $0.roleID == roleID }
            VStack(spacing: 0) {
                HStack(spacing: Space.s) {
                    RoleBadge(kind: role.role, name: model.roleKindName(role.role))
                    if role.isOrchestrator {
                        Text(role.name).font(.body.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(model.t("role.namePlaceholder"), text: roleBinding(roleID).name)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }
                    if !role.isOrchestrator {
                        Button(role: .destructive) {
                            pendingDeleteRole = roleID
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(model.t("team.delete"))
                    }
                }
                .padding(Space.l)
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        if role.isOrchestrator {
                            Label(model.t("role.orchestratorNote"), systemImage: "info.circle")
                                .font(.sfCaption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        RoleEditorForm(role: roleBinding(roleID), issues: issues)
                    }
                    .padding(Space.l)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.cardBg)
        } else {
            ContentUnavailableView {
                Label(model.t("team.selectHint.title"), systemImage: "cursorarrow.rays")
            } description: {
                Text(model.t("team.selectHint.desc"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cardBg)
        }
    }

    /// A stable two-way binding to one role in the team's strategy, keyed by id.
    private func roleBinding(_ roleID: AgentRole.ID) -> Binding<AgentRole> {
        Binding(
            get: {
                team.strategy.roles.first(where: { $0.id == roleID })
                    ?? team.strategy.roles[0]
            },
            set: { newValue in
                if let i = team.strategy.roles.firstIndex(where: { $0.id == roleID }) {
                    team.strategy.roles[i] = newValue
                }
            }
        )
    }
}

private struct TeamViewPreviewHost: View {
    @State private var model: AppModel = {
        let m = AppModel()
        m.savedTeams = [SavedTeam(name: "Backend refactor team",
                                  strategy: StrategyLibrary.orchestratorWorkers())]
        m.selectedTeamID = m.savedTeams.first!.id
        return m
    }()
    var body: some View {
        TeamView(team: model.teamBinding(model.selectedTeamID!))
            .environment(model)
            .tint(Theme.accent)
            .frame(width: 1000, height: 680)
    }
}

#Preview { TeamViewPreviewHost() }
#Preview("Dark") { TeamViewPreviewHost().preferredColorScheme(.dark) }
