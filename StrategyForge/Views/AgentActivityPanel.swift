//
//  AgentActivityPanel.swift
//  StrategyForge
//
//  A right-side "what are the agents doing" panel (à la Claude Code): the active
//  agent + model, an elapsed timer, the task list (TodoWrite), tokens/cost, and a
//  live timeline of every tool step and delegation.
//

import SwiftUI

struct AgentActivityPanel: View {
    @Environment(AppModel.self) private var model
    var vm: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Text(model.t("activity.title"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                if vm.isRunning {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                    Text(model.t("activity.running")).font(.sfCaption2).foregroundStyle(Theme.success)
                }
            }
            .padding(Space.m)
            .background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    statusCard
                    teamSection
                    if !vm.todos.isEmpty { tasksSection }
                    timelineSection
                }
                .padding(Space.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
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
                        .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
    }

    // MARK: Team

    /// The roster for this turn: the orchestrator plus every subagent it delegated
    /// to, each showing whether it's active now or already done.
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.team")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            agentRow(name: model.t("activity.orchestrator"),
                     icon: "brain.head.profile",
                     active: vm.activeSubagent == nil && vm.isRunning)
            ForEach(vm.agentsInvolved, id: \.self) { agent in
                agentRow(name: agent, icon: "person.fill",
                         active: agent == vm.activeSubagent && vm.isRunning)
            }
            if vm.agentsInvolved.isEmpty {
                Text(model.t("activity.soloNote"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func agentRow(name: String, icon: String, active: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(active ? Theme.accent : .secondary)
                .frame(width: 16)
            Text(name)
                .font(.sfCaption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            if active {
                HStack(spacing: 3) {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                        .foregroundStyle(Theme.success)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(model.t("activity.active")).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
            } else {
                Text(model.t("activity.done")).font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.tasks")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
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
        default: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    // MARK: Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.steps")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            if vm.timeline.isEmpty {
                Text(model.t("activity.empty")).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(vm.timeline.enumerated()), id: \.element.id) { idx, step in
                    stepRow(step, isActive: vm.isRunning && idx == vm.timeline.count - 1)
                }
            }
        }
    }

    private func stepRow(_ step: ActivityStep, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: step.isDelegation ? "arrow.turn.down.right" : toolIcon(step.title))
                .font(.system(size: 10))
                .foregroundStyle(step.isDelegation ? Theme.accent : (isActive ? Theme.success : .secondary))
                .frame(width: 16)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive && !step.isDelegation)
            Text(phrase(step))
                .font(.sfCaption2.weight(step.isDelegation || isActive ? .semibold : .regular))
                .foregroundStyle(step.isDelegation ? Theme.accent : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if let start = vm.turnStartedAt {
                Text(elapsed(from: start, to: step.at))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    /// A human sentence for a step ("Reading App.swift", "Running npm test").
    private func phrase(_ step: ActivityStep) -> String {
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

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text.magnifyingglass"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": return "pencil"
        case "Bash": return "terminal"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }

    // MARK: Helpers

    private func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
