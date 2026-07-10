//
//  TeamView.swift
//  StrategyForge
//
//  The dedicated, in-window "Team" section: a visual canvas of the chat's agents
//  (orchestrator + subagents as interactive cards) with an inline detail panel to
//  configure the selected agent, plus add/remove. Replaces the cramped modal so
//  building a team feels visual and simple.
//

import SwiftUI

struct TeamView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var config: Configuration

    @State private var selectedRoleID: AgentRole.ID?
    @State private var showSaveTeam = false
    @State private var newTeamName = ""

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
            if selectedRoleID == nil {
                selectedRoleID = config.strategy.orchestrator?.id ?? config.strategy.roles.first?.id
            }
        }
        .alert(model.t("team.save.title"), isPresented: $showSaveTeam) {
            TextField(model.t("team.save.placeholder"), text: $newTeamName)
            Button(model.t("common.cancel"), role: .cancel) { newTeamName = "" }
            Button(model.t("team.save.confirm")) {
                model.saveTeam(named: newTeamName, from: config.id)
                newTeamName = ""
            }
        } message: {
            Text(model.t("team.save.message"))
        }
    }

    // MARK: - Canvas (left)

    private var canvas: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if let orch = config.strategy.orchestrator {
                        sectionLabel("team.orchestrator.section", systemImage: "crown.fill")
                        agentCard(orch, wide: true)
                    }

                    HStack {
                        sectionLabel("team.members.section", systemImage: "person.2.fill")
                        Spacer()
                        Text(model.t("team.members.count", config.strategy.subagentRoles.count))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: Space.m)],
                              alignment: .leading, spacing: Space.m) {
                        ForEach(config.strategy.subagentRoles) { role in
                            agentCard(role, wide: false)
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
                Text(model.t("team.title")).font(.sfDisplay)
                Text(config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name)
                    .font(.sfCallout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            costPill
            teamsMenu
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

    /// The saved-team library menu: apply an existing preset, save the current team
    /// as a new preset, or overwrite one.
    private var teamsMenu: some View {
        Menu {
            if !model.savedTeams.isEmpty {
                Section(model.t("team.library.apply")) {
                    ForEach(model.savedTeams) { team in
                        Button {
                            model.applyTeam(team, to: config.id)
                            selectedRoleID = config.strategy.orchestrator?.id
                        } label: {
                            Label("\(team.name)  ·  \(team.strategy.roles.count) 👥", systemImage: "person.3.fill")
                        }
                    }
                }
                Section(model.t("team.library.update")) {
                    ForEach(model.savedTeams) { team in
                        Button(team.name) { model.updateTeam(team.id, from: config.id) }
                    }
                }
                Divider()
            }
            Button {
                newTeamName = ""
                showSaveTeam = true
            } label: {
                Label(model.t("team.save.new"), systemImage: "square.and.arrow.down.on.square")
            }
        } label: {
            Label(model.t("team.library"), systemImage: "bookmark")
        }
        .menuStyle(.button)
        .controlSize(.large)
        .fixedSize()
    }

    private var costPill: some View {
        let cost = CostEstimator.estimate(config.strategy)
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

    private func agentCard(_ role: AgentRole, wide: Bool) -> some View {
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(role.name).font(.sfCallout.weight(.semibold)).lineLimit(1)
                        Text(model.roleKindName(role.role))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(role.role.tint)
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
            if let id = model.addRole(to: config.id) {
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
           let role = config.strategy.roles.first(where: { $0.id == roleID }) {
            let issues = config.strategy.validate().filter { $0.roleID == roleID }
            VStack(spacing: 0) {
                // Panel header.
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
                            model.deleteRole(roleID, from: config.id)
                            selectedRoleID = config.strategy.orchestrator?.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(model.t("team.delete"))
                    }
                }
                .padding(Space.m)
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
                    .padding(Space.m)
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

    /// A stable two-way binding to one role in the strategy, keyed by id.
    private func roleBinding(_ roleID: AgentRole.ID) -> Binding<AgentRole> {
        Binding(
            get: {
                config.strategy.roles.first(where: { $0.id == roleID })
                    ?? config.strategy.roles[0]
            },
            set: { newValue in
                if let i = config.strategy.roles.firstIndex(where: { $0.id == roleID }) {
                    config.strategy.roles[i] = newValue
                }
            }
        )
    }
}

private struct TeamViewPreviewHost: View {
    @State private var model: AppModel = {
        let m = AppModel()
        m.configurations = [Configuration(name: "Backend refactor team",
                                          strategy: StrategyLibrary.orchestratorWorkers())]
        m.selectedConfigID = m.configurations.first!.id
        return m
    }()
    var body: some View {
        TeamView(config: model.configurationBinding(model.selectedConfigID!))
            .environment(model)
            .tint(Theme.accent)
            .frame(width: 1000, height: 680)
    }
}

#Preview { TeamViewPreviewHost() }
#Preview("Dark") { TeamViewPreviewHost().preferredColorScheme(.dark) }
