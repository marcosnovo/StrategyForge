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
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    statusCard
                    if !vm.todos.isEmpty { tasksSection }
                    timelineSection
                }
                .padding(Space.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
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
                ForEach(vm.timeline) { step in stepRow(step) }
            }
        }
    }

    private func stepRow(_ step: ActivityStep) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: step.isDelegation ? "arrow.turn.down.right" : toolIcon(step.title))
                .font(.system(size: 10))
                .foregroundStyle(step.isDelegation ? Theme.accent : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.isDelegation ? "→ \(step.title)" : step.title)
                    .font(.sfCaption2.weight(step.isDelegation ? .semibold : .regular))
                    .foregroundStyle(step.isDelegation ? Theme.accent : .primary)
                if let detail = step.detail {
                    Text(detail).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.xs)
            if let start = vm.turnStartedAt {
                Text(elapsed(from: start, to: step.at))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
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
