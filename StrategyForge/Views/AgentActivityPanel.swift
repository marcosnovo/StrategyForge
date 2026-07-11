//
//  AgentActivityPanel.swift
//  StrategyForge
//
//  A right-side "what are the agents doing" panel (à la Claude Code): the active
//  agent + model, an elapsed timer, the task list (TodoWrite), tokens/cost, and a
//  live timeline of every tool step and delegation.
//

import SwiftUI

/// What the far-right detail column shows: one agent's activity, or all steps.
enum AgentFocus: Hashable {
    case orchestrator
    case sub(String)
    case allSteps

    /// Does this timeline step belong to the focused view?
    func matches(_ step: ActivityStep) -> Bool {
        switch self {
        case .orchestrator: return step.agent == nil
        case .sub(let name): return StrategyDiagramView.titlesMatch(step.agent ?? "", name)
        case .allSteps: return true
        }
    }
}

struct AgentActivityPanel: View {
    @Environment(AppModel.self) private var model
    var vm: ChatViewModel
    /// The agent whose detail column is open (nil = closed). Bound to the parent
    /// so the drill-down column lives at the far right of the window.
    @Binding var focus: AgentFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAgent: AgentFocus?
    @State private var showDiagram = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                // Same title treatment as the Chats list and the chat header (a
                // sfCardTitle line + a quiet subrow), so the three column headers
                // read at one harmonious size instead of big/tiny/big.
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.strategyDisplayName(vm.config.strategy))
                        .font(.sfCardTitle).lineLimit(1)
                    Text(model.t("activity.title"))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1)
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
                VStack(alignment: .leading, spacing: Space.m) {
                    statusCard
                    teamSection.panelCard()
                    if !vm.todos.isEmpty { tasksSection.panelCard() }
                    stepsSection.panelCard()
                    diagramCard.panelCard()
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
            if let goal = goalText {
                HStack(spacing: 6) {
                    Image(systemName: "target").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text(goal).font(.sfCallout.weight(.semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                stat("person.2.fill", "\(vm.config.strategy.roles.count)")
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

    /// The current objective/goal name: the in-progress task, else the chat title.
    private var goalText: String? {
        if let t = vm.todos.first(where: { $0.status == "in_progress" }), !t.content.isEmpty { return t.content }
        let name = vm.config.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.sfCaption2.weight(.medium))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: text)
        }
        .foregroundStyle(Theme.secondaryOnMaterial)
    }

    // MARK: Diagram (bottom, collapsible)

    /// The live topology at the bottom of the panel — visible unless collapsed.
    private var diagramCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showDiagram.toggle() } } label: {
                HStack {
                    Text(model.t("activity.tab.diagram")).font(.sfFieldLabel)
                        .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                    Spacer()
                    Image(systemName: showDiagram ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDiagram {
                StrategyDiagramView(strategy: vm.config.strategy,
                                    activeAgent: vm.activeSubagent,
                                    isLive: vm.isRunning,
                                    compact: true)
                    .frame(height: 240)
            }
        }
    }

    // MARK: Team (all agents, listed from the start)

    private func titleCase(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
    private var orchestratorName: String {
        (vm.config.strategy.orchestrator?.name).map(titleCase) ?? model.t("activity.orchestrator")
    }
    private var subagentNames: [String] {
        vm.config.strategy.subagentRoles.map { titleCase($0.name) }
    }

    enum AgentStatus { case active, done, idle }

    /// The whole team, listed from the start, each with its objective, live status
    /// and a filling progress bar (Claude-style).
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("activity.team")).font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
            agentRow(name: orchestratorName, icon: "brain.head.profile", target: .orchestrator,
                     objective: orchestratorObjective, status: orchestratorStatus)
            ForEach(vm.config.strategy.subagentRoles) { role in
                let name = titleCase(role.name)
                agentRow(name: name, icon: "person.fill", target: .sub(name),
                         objective: role.description, status: status(forSubagent: name))
            }
        }
    }

    private var orchestratorObjective: String {
        let d = vm.config.strategy.orchestrator?.description ?? ""
        return d.isEmpty ? model.t("activity.orchestrator.role") : d
    }
    private var orchestratorStatus: AgentStatus {
        if vm.isRunning { return .active }
        return vm.hasFinishedActivity ? .done : .idle
    }
    private func status(forSubagent name: String) -> AgentStatus {
        let active = vm.isRunning && StrategyDiagramView.titlesMatch(vm.activeSubagent ?? "", name)
        if active { return .active }
        let hasWork = vm.timeline.contains { StrategyDiagramView.titlesMatch($0.agent ?? "", name) }
        return hasWork ? .done : .idle
    }

    /// The tool steps attributed to one agent (Claude-Code-style per-agent metrics
    /// derived from the live timeline — the orchestrator owns the un-delegated steps).
    private func agentSteps(_ target: AgentFocus) -> [ActivityStep] {
        vm.timeline.filter { step in
            guard !step.isDelegation else { return false }
            switch target {
            case .orchestrator: return step.agent == nil
            case .sub(let n): return StrategyDiagramView.titlesMatch(step.agent ?? "", n)
            case .allSteps: return true
            }
        }
    }

    /// (tools used, elapsed span) for one agent, or nil span when it hasn't spanned time.
    private func agentStats(_ target: AgentFocus) -> (tools: Int, span: String?) {
        let steps = agentSteps(target)
        guard let first = steps.first?.at, let last = steps.last?.at else { return (0, nil) }
        let span = last.timeIntervalSince(first) >= 1 ? activityElapsed(from: first, to: last) : nil
        return (steps.count, span)
    }

    // MARK: Steps (recent + "see all" on the right)

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("activity.steps")).font(.sfFieldLabel)
                    .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Spacer()
                if !vm.timeline.isEmpty {
                    Button { focus = .allSteps } label: {
                        HStack(spacing: 2) {
                            Text(model.t("activity.seeAll")); Image(systemName: "chevron.right").font(.system(size: 8))
                        }
                        .font(.sfCaption2.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            if vm.timeline.isEmpty {
                Text(model.t("activity.empty")).font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
            } else {
                ForEach(Array(vm.timeline.suffix(6).enumerated()), id: \.element.id) { idx, step in
                    ActivityStepRow(step: step, startedAt: vm.turnStartedAt,
                                    isActive: vm.isRunning && step.id == vm.timeline.last?.id)
                }
            }
        }
    }

    private func agentRow(name: String, icon: String, target: AgentFocus,
                          objective: String, status: AgentStatus) -> some View {
        let isOpen = focus == target
        return Button {
            focus = isOpen ? nil : target
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Image(systemName: icon).font(.system(size: 11))
                        .foregroundStyle(status == .active ? Theme.success : .secondary)
                        .frame(width: 16)
                    Text(name)
                        .font(.sfCaption2.weight(status == .active || isOpen ? .semibold : .medium))
                        .foregroundStyle(status == .idle ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    statusBadge(status)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isOpen ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                if !objective.isEmpty {
                    Text(objective)
                        .font(.system(size: 10)).foregroundStyle(Theme.secondaryOnMaterial)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.leading, 16 + Space.s)
                }
                let stats = agentStats(target)
                if stats.tools > 0 {
                    HStack(spacing: Space.s) {
                        Label("\(stats.tools)", systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 9, weight: .medium))
                            .contentTransition(.numericText())
                        if let span = stats.span {
                            Label(span, systemImage: "clock")
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .foregroundStyle(Theme.tertiaryOnMaterial)
                    .padding(.leading, 16 + Space.s)
                }
                progressBar(status).padding(.leading, 16 + Space.s)
            }
            .padding(.horizontal, Space.s).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(status == .active ? Theme.success.opacity(0.10)
                      : (isOpen ? Theme.accentSoft
                         : (hoveredAgent == target ? Theme.hairline.opacity(0.6) : .clear))))
            .overlay(alignment: .leading) {
                if status == .active {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.success)
                        .frame(width: 2.5).padding(.vertical, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: status == .active)
        .onHover { hovering in
            if hovering { hoveredAgent = target }
            else if hoveredAgent == target { hoveredAgent = nil }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: AgentStatus) -> some View {
        switch status {
        case .active:
            HStack(spacing: 3) {
                Image(systemName: "circle.fill").font(.system(size: 5))
                    .symbolEffect(.pulse, options: .repeating)
                Text(model.t("activity.running")).font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.success)
        case .done:
            Label(model.t("activity.done"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.success)
        case .idle:
            Label(model.t("activity.idle"), systemImage: "hourglass")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondaryOnMaterial)
        }
    }

    /// A filling bar per agent: animating while active, full when done, empty idle.
    @ViewBuilder
    private func progressBar(_ status: AgentStatus) -> some View {
        switch status {
        case .active:
            ProgressView().progressViewStyle(.linear).tint(Theme.success)
                .controlSize(.small).frame(height: 4)
        case .done:
            Capsule().fill(Theme.success).frame(height: 4)
        case .idle:
            Capsule().fill(Theme.secondaryOnMaterial.opacity(0.25)).frame(height: 4)
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("activity.tasks")).font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Spacer()
                progressDots
            }
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

    /// A compact "▪▪▪▫▫" progress readout for the task list (Claude-Code-style),
    /// one square per todo: filled=done, accent=in-progress, hollow=pending.
    private var progressDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(vm.todos.enumerated()), id: \.offset) { _, todo in
                let color: Color = todo.status == "completed" ? Theme.success
                    : (todo.status == "in_progress" ? Theme.accent : Theme.secondaryOnMaterial.opacity(0.3))
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 6, height: 6)
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

    // MARK: Helpers

    private func elapsed(from: Date, to: Date) -> String { activityElapsed(from: from, to: to) }
    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - Panel section card (reference "Group Info" look)

private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1))
    }
}
extension View {
    func panelCard() -> some View { modifier(PanelCard()) }
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
        case .allSteps: return model.t("activity.allSteps")
        }
    }
    private var icon: String {
        switch focus {
        case .orchestrator: return "brain.head.profile"
        case .sub: return "person.fill"
        case .allSteps: return "list.bullet.rectangle"
        }
    }
    private var isActiveAgent: Bool {
        guard vm.isRunning else { return false }
        switch focus {
        case .orchestrator: return vm.activeSubagent == nil
        case .sub(let name): return StrategyDiagramView.titlesMatch(vm.activeSubagent ?? "", name)
        case .allSteps: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
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
        .background(.regularMaterial)
    }
}
