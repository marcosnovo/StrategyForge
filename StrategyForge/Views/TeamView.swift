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
    enum Mode { case saved, draft }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var team: SavedTeam
    /// `.draft` = not yet saved (shows "Create team"); `.saved` = library team.
    var mode: Mode = .saved
    /// Commit a draft into the saved library. Only used in `.draft` mode.
    var onCommit: () -> Void = {}

    @State private var selectedRoleID: AgentRole.ID?
    @State private var confirmDeleteTeam = false
    @State private var pendingDeleteRole: AgentRole.ID?
    @State private var saveTask: Task<Void, Never>?

    private var strategy: Strategy { team.strategy }
    private var isDraft: Bool { mode == .draft }

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
        // Persist edits, coalesced so typing doesn't write the store per keystroke.
        // Drafts are in-memory only — never autosaved until the user hits "Create".
        .onChange(of: team) {
            guard !isDraft else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                model.save()
            }
        }
        .onDisappear { if !isDraft { model.save() } }
    }

    // MARK: - Canvas (left)

    private var canvas: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    // Visualize the whole strategy (like the picker), now with room
                    // to breathe — the topology reads at a glance before the cards.
                    StrategyDiagramView(
                        strategy: strategy,
                        compact: false,
                        onSelectNode: { rid in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedRoleID = rid }
                        },
                        selectedRoleID: selectedRoleID
                    )
                        .frame(height: StrategyDiagramView.preferredHeight(for: strategy))
                        .frame(maxWidth: .infinity)
                        .padding(Space.s)
                        // The team canvas floats on a soft rounded glass panel so the
                        // aurora reads faintly through the topology (Aetheris surface).
                        .glassPanel(cornerRadius: Theme.corner)
                        .staggeredAppear(index: 0)

                    if let orch = strategy.orchestrator {
                        HStack(spacing: Space.xs) {
                            sectionLabel("team.orchestrator.section", systemImage: "crown.fill")
                            InfoPopoverButton(text: model.t("glossary.orchestrator"))
                        }
                        agentCard(orch)
                            .staggeredAppear(index: 0)
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
                        InfoPopoverButton(text: model.t("glossary.worker"))
                        Spacer()
                        Text(model.t("team.members.count", strategy.subagentRoles.count))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.m)],
                              alignment: .leading, spacing: Space.m) {
                        ForEach(Array(strategy.subagentRoles.enumerated()), id: \.element.id) { index, role in
                            agentCard(role)
                                .staggeredAppear(index: index + 1)
                        }
                        // The add tile joins the cascade last instead of popping
                        // in ahead of its rising neighbors.
                        addCard
                            .staggeredAppear(index: strategy.subagentRoles.count + 1)
                    }

                    connectionNote

                    // Evals: measure the team against a scenario suite before trusting it.
                    EvalsView(strategy: $team.strategy)
                        .staggeredAppear(index: strategy.subagentRoles.count + 2)
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            if isDraft {
                // A clear, obvious "‹ Strategies" chip back to the picker (discards
                // the draft) — reads as navigation, not a label.
                Button { model.draftTeam = nil } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(model.t("team.draft.back")).font(.sfCallout.weight(.medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.insetBg))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(model.t("team.draft.back"))
            }
            VStack(alignment: .leading, spacing: 2) {
                TextField(model.t("team.name"), text: $team.name)
                    .textFieldStyle(.plain)
                    // sfCardTitle (not the huge display) so long names ("Team lead +
                    // parallel workers") fit the crowded header without truncating.
                    .font(isDraft ? .sfCardTitle : .sfDisplay)
                    .lineLimit(1)
                if isDraft {
                    Label(model.t("team.draft.badge"), systemImage: "pencil.line")
                        .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.warning)
                } else {
                    Text(model.strategyDisplayName(strategy))
                        .font(.sfCallout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            costPill
                .fixedSize()
            if isDraft {
                // Not saved yet — "Create" commits it (Back, top-left, discards).
                Button {
                    onCommit()
                } label: {
                    Label(model.t("team.create.commit"), systemImage: "checkmark")
                }
                .buttonStyle(.moon)
                .controlSize(.large)
                .fixedSize()
            } else {
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
                .help(model.t("common.more"))
                Button {
                    model.useTeamInNewChat(team)
                } label: {
                    Label(model.t("team.useInChat"), systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.moon)
                .controlSize(.large)
                .fixedSize()
                Button {
                    model.save()
                    model.flashSuccess(model.t("banner.saved"))
                } label: {
                    Label(model.t("editor.save"), systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize()
            }
        }
        .padding(Space.l)
        .zoomWindowOnDoubleClick()
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
            Image(systemName: "bolt.fill").scaledFont(9)
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
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(role.name).font(.sfCallout.weight(.semibold)).lineLimit(1)
                        Text(model.roleKindName(role.role))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
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
                        Image(systemName: role.model.tierIcon).scaledFont(9).foregroundStyle(.secondary)
                    }
                    Text(role.modelDisplayName).font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Rounded card surface; selected agent glows in its role hue
            // (orchestrator coral, workers teal) as a soft wash + border.
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(selected ? role.role.tint.opacity(0.10) : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(selected ? role.role.tint : Theme.hairline,
                              lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift()
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
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.accentSoft.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift()
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
                        .help(model.t(role.isOrchestrator ? "glossary.orchestrator" : "glossary.worker"))
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
