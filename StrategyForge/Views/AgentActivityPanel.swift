//
//  AgentActivityPanel.swift
//  StrategyForge
//
//  A right-side "what are the agents doing" panel (à la Claude Code): the active
//  agent + model, an elapsed timer, the task list (TodoWrite), tokens/cost, and a
//  live timeline of every tool step and delegation.
//

import SwiftUI

/// Which agent's detailed activity is being drilled into on the far-right panel.
enum AgentFocus: Hashable {
    case orchestrator
    case sub(String)

    /// Does this timeline step belong to the focused agent?
    func matches(_ step: ActivityStep) -> Bool {
        switch self {
        case .orchestrator: return step.agent == nil
        case .sub(let name): return step.agent == name
        }
    }
}

enum ActivityPanelMode: String, CaseIterable { case timeline, diagram }

struct AgentActivityPanel: View {
    @Environment(AppModel.self) private var model
    var vm: ChatViewModel
    /// The agent whose detail column is open (nil = closed). Bound to the parent
    /// so the drill-down column lives at the far right of the window.
    @Binding var focus: AgentFocus?
    @State private var mode: ActivityPanelMode = .timeline
    @State private var hoveredAgent: AgentFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("activity.title"))
                        .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                    Text(model.strategyDisplayName(vm.config.strategy))
                        .font(.sfCallout.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                if vm.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").font(.system(size: 6))
                            .symbolEffect(.pulse, options: .repeating)
                        Text(model.t("activity.running")).font(.sfCaption2.weight(.semibold))
                    }
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
                    .glassEffect(.regular.tint(Theme.success.opacity(0.18)), in: .capsule)
                } else if vm.hasFinishedActivity {
                    Label(model.t("activity.done.turn"), systemImage: "checkmark.circle.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.success)
                }
            }
            .padding(Space.m)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    statusCard
                    teamSection
                    modePicker
                    if mode == .timeline {
                        if !vm.todos.isEmpty { tasksSection }
                        timelineSection
                    } else {
                        diagramSection
                    }
                }
                .padding(Space.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }

    // MARK: Status

    private var statusCard: some View {
        let subagent = vm.activeSubagent
        let modelName = vm.config.strategy.orchestrator?.model.displayName ?? "—"
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                if vm.isRunning { WorkingLogo(size: 22) }
                else { Image(systemName: "sparkle").foregroundStyle(Theme.accent).frame(width: 22, height: 22) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(subagent ?? model.t("activity.orchestrator"))
                        .font(.sfCallout.weight(.semibold))
                        .foregroundStyle(subagent == nil ? .primary : Theme.accent)
                    Text(subagent == nil ? modelName : model.t("activity.viaOrchestrator"))
                        .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.secondaryOnMaterial)
                }
                Spacer()
            }
            HStack(spacing: Space.m) {
                if let start = vm.turnStartedAt, vm.isRunning {
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        stat("clock", elapsed(from: start, to: ctx.date))
                    }
                }
                if vm.totalTokens > 0 { stat("circle.hexagongrid", formatTokens(vm.totalTokens)) }
                if vm.totalCostUSD > 0 { stat("dollarsign.circle", String(format: "$%.2f", vm.totalCostUSD)) }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.innerCorner))
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.sfCaption2.weight(.medium))
        }
        .foregroundStyle(Theme.secondaryOnMaterial)
    }

    // MARK: Mode switch + diagram

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(model.t("activity.tab.steps")).tag(ActivityPanelMode.timeline)
            Text(model.t("activity.tab.diagram")).tag(ActivityPanelMode.diagram)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// The live topology: the strategy diagram with the working agent's node lit.
    private var diagramSection: some View {
        StrategyDiagramView(strategy: vm.config.strategy,
                            activeAgent: vm.activeSubagent,
                            isLive: vm.isRunning,
                            compact: true)
            .frame(height: 280)
    }

    // MARK: Team

    /// The roster for this turn: the orchestrator plus every subagent it delegated
    /// to, each showing whether it's active now or already done.
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(model.t("activity.team")).font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
            agentRow(name: model.t("activity.orchestrator"),
                     icon: "brain.head.profile",
                     target: .orchestrator,
                     active: vm.activeSubagent == nil && vm.isRunning)
            ForEach(vm.agentsInvolved, id: \.self) { agent in
                agentRow(name: agent, icon: "person.fill",
                         target: .sub(agent),
                         active: agent == vm.activeSubagent && vm.isRunning)
            }
            if vm.agentsInvolved.isEmpty {
                Text(model.t("activity.soloNote"))
                    .font(.system(size: 10)).foregroundStyle(Theme.tertiaryOnMaterial)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func agentRow(name: String, icon: String, target: AgentFocus, active: Bool) -> some View {
        let isOpen = focus == target
        let count = vm.timeline.filter { target.matches($0) }.count
        return Button {
            focus = isOpen ? nil : target
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? Theme.accent : .secondary)
                    .frame(width: 16)
                Text(name)
                    .font(.sfCaption2.weight(active || isOpen ? .semibold : .regular))
                    .foregroundStyle(active || isOpen ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                if active {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                        .foregroundStyle(Theme.success)
                        .symbolEffect(.pulse, options: .repeating)
                } else if count > 0 {
                    // This agent did work and isn't the active one → its task is done.
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                        .foregroundStyle(Theme.success)
                }
                if count > 0 {
                    Text("\(count)").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.tertiaryOnMaterial)
                }
                // Disclosure arrow → opens the far-right detail column.
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isOpen ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, Space.s).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isOpen ? Theme.accentSoft
                      : (hoveredAgent == target ? Theme.hairline.opacity(0.7) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredAgent = target }
            else if hoveredAgent == target { hoveredAgent = nil }
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.tasks")).font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
            ForEach(Array(vm.todos.enumerated()), id: \.offset) { _, todo in
                HStack(alignment: .top, spacing: Space.s) {
                    todoIcon(todo.status)
                    Text(todo.content)
                        .font(.sfCaption2)
                        .strikethrough(todo.status == "completed")
                        .foregroundStyle(todo.status == "completed" ? .tertiary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func todoIcon(_ status: String) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case "in_progress": Image(systemName: "circle.dotted.circle").foregroundStyle(Theme.accent)
        default: Image(systemName: "circle").foregroundStyle(Theme.tertiaryOnMaterial)
        }
    }

    // MARK: Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.steps")).font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
            if vm.timeline.isEmpty {
                Text(model.t("activity.empty")).font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
            } else {
                ForEach(Array(vm.timeline.enumerated()), id: \.element.id) { idx, step in
                    ActivityStepRow(step: step, startedAt: vm.turnStartedAt,
                                    isActive: vm.isRunning && idx == vm.timeline.count - 1)
                }
            }
        }
    }

    // MARK: Helpers

    private func elapsed(from: Date, to: Date) -> String { activityElapsed(from: from, to: to) }
    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - Shared step rendering

/// One timeline step, reused by the activity panel and the per-agent drill-down.
struct ActivityStepRow: View {
    @Environment(AppModel.self) private var model
    let step: ActivityStep
    let startedAt: Date?
    var isActive: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: step.isDelegation ? "arrow.turn.down.right" : activityToolIcon(step.title))
                .font(.system(size: step.isDelegation || isActive ? 11 : 10, weight: step.isDelegation ? .semibold : .regular))
                .foregroundStyle(step.isDelegation ? Theme.accent : (isActive ? Theme.success : .secondary))
                .frame(width: 16)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive && !step.isDelegation)
            Text(activityPhrase(step, model))
                .font(.sfCaption2.weight(step.isDelegation || isActive ? .semibold : .regular))
                .foregroundStyle(step.isDelegation ? Theme.accent : (isActive ? .primary : .secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if let start = startedAt {
                Text(activityElapsed(from: start, to: step.at))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiaryOnMaterial)
            }
        }
        .padding(.vertical, step.isDelegation ? 6 : 2)
        .padding(.horizontal, step.isDelegation ? Space.s : 0)
        .background {
            if step.isDelegation {
                RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft)
            } else if isActive {
                RoundedRectangle(cornerRadius: 8).fill(Theme.success.opacity(0.10))
            }
        }
        .overlay(alignment: .leading) {
            if step.isDelegation || isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(step.isDelegation ? Theme.accent : Theme.success)
                    .frame(width: 2.5)
                    .padding(.vertical, 2)
                    .offset(x: -Space.s)
            }
        }
    }
}

/// A human sentence for a step ("Reading App.swift", "Running npm test").
func activityPhrase(_ step: ActivityStep, _ model: AppModel) -> String {
    if step.isDelegation { return model.t("act.delegated", step.title) }
    let target = step.detail ?? ""
    func withTarget(_ key: String) -> String {
        target.isEmpty ? model.t("act.using", step.title) : model.t(key, target)
    }
    switch step.title {
    case "Read": return withTarget("act.reading")
    case "Edit", "MultiEdit", "NotebookEdit": return withTarget("act.editing")
    case "Write": return withTarget("act.writing")
    case "Bash": return withTarget("act.running")
    case "Grep", "Glob": return withTarget("act.searching")
    case "WebFetch", "WebSearch": return withTarget("act.fetching")
    case "TodoWrite": return model.t("act.planning")
    default:
        return target.isEmpty ? model.t("act.using", step.title)
                              : model.t("act.using", "\(step.title) · \(target)")
    }
}

func activityToolIcon(_ name: String) -> String {
    switch name {
    case "Read": return "doc.text.magnifyingglass"
    case "Write", "Edit", "MultiEdit", "NotebookEdit": return "pencil"
    case "Bash": return "terminal"
    case "Grep", "Glob": return "magnifyingglass"
    case "WebFetch", "WebSearch": return "globe"
    default: return "wrench.and.screwdriver"
    }
}

func activityElapsed(from: Date, to: Date) -> String {
    let s = max(0, Int(to.timeIntervalSince(from)))
    return s < 60 ? "\(s)s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
}

// MARK: - Per-agent drill-down

/// The far-right column: one agent's own activity, opened from a team row's arrow.
struct SubagentDetailPanel: View {
    @Environment(AppModel.self) private var model
    var vm: ChatViewModel
    let focus: AgentFocus
    var onClose: () -> Void

    private var steps: [ActivityStep] { vm.timeline.filter { focus.matches($0) } }
    private var title: String {
        switch focus {
        case .orchestrator: return model.t("activity.orchestrator")
        case .sub(let name): return name
        }
    }
    private var isActiveAgent: Bool {
        guard vm.isRunning else { return false }
        switch focus {
        case .orchestrator: return vm.activeSubagent == nil
        case .sub(let name): return vm.activeSubagent == name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: focus == .orchestrator ? "brain.head.profile" : "person.fill")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.sfCallout.weight(.semibold)).lineLimit(1)
                    Text(model.t("activity.agentDetail")).font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                }
                Spacer()
                if isActiveAgent {
                    Image(systemName: "circle.fill").font(.system(size: 6))
                        .foregroundStyle(Theme.success).symbolEffect(.pulse, options: .repeating)
                }
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.secondaryOnMaterial)
                .help(model.t("common.done"))
                .accessibilityLabel(model.t("common.done"))
            }
            .padding(Space.m)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zIndex(1)

            if steps.isEmpty {
                VStack(spacing: Space.s) {
                    Image(systemName: "hourglass").font(.title2).foregroundStyle(Theme.tertiaryOnMaterial)
                    Text(model.t("activity.empty")).font(.sfCaption2)
                        .foregroundStyle(Theme.secondaryOnMaterial).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.l)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                            ActivityStepRow(step: step, startedAt: vm.turnStartedAt,
                                            isActive: isActiveAgent && idx == steps.count - 1)
                        }
                    }
                    .padding(Space.m)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
