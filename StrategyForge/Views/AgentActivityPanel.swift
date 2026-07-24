//
//  AgentActivityPanel.swift
//  StrategyForge
//
//  A right-side "what are the agents doing" panel (à la Claude Code): the active
//  agent + model, an elapsed timer, the task list (TodoWrite), tokens/cost, and a
//  live timeline of every tool step and delegation.
//

import SwiftUI
import AppKit

/// What the far-right detail column shows: one agent's activity, or all steps.
enum AgentFocus: Hashable {
    case orchestrator
    case sub(String)
    case allSteps

    /// Does this timeline step belong to the focused view?
    func matches(_ step: ActivityStep) -> Bool {
        switch self {
        case .orchestrator: return step.agent == nil
        case .sub(let name): return AgentNameMatcher.titlesMatch(step.agent ?? "", name)
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
    /// When set (and not running), the panel previews this RECOMMENDED strategy in the
    /// header + diagram, so the right side reflects the pending recommendation.
    var previewStrategy: Strategy? = nil
    /// The name of the previewed option (Economy / Recommended / Max), for the label.
    var previewLabel: String? = nil
    /// A one-line reason the recommendation is worth considering (the tier's tradeoff
    /// note), shown in the selected-vs-recommended comparison.
    var previewReason: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAgent: AgentFocus?
    /// ChatGPT-calm: the topology diagram is opt-in (heavy for the resting state) — the
    /// panel opens as narration + steps, with "Show diagram" one tap away.
    @State private var showDiagram = false
    /// The team list starts collapsed so the panel reads at a glance.
    @State private var showTeam = false
    @State private var previewingFiles = false
    @State private var showHistory = false
    @State private var showCompare = false

    /// The strategy to show: the recommendation preview when idle, else the live team.
    private var shownStrategy: Strategy {
        (!vm.isRunning ? previewStrategy : nil) ?? vm.config.strategy
    }
    private var isPreviewing: Bool { !vm.isRunning && previewStrategy != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                // No big title here — the cards below already show the team, so the
                // header is just a quiet eyebrow + the current status/preview badge
                // (removes the redundant, cluttered strategy-name row).
                Text(model.t("activity.title"))
                    .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Spacer()
                if isPreviewing {
                    // Name the chosen option so the preview badge tracks the selection.
                    Label(previewLabel ?? model.t("activity.preview"), systemImage: "sparkles")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, Space.s).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accentSoft))
                } else if vm.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").font(.system(size: 6))
                            .symbolEffect(.pulse, options: .repeating)
                        Text(model.t("activity.running")).font(.sfCaption2.weight(.semibold))
                    }
                    .foregroundStyle(Theme.tealText)
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
                    .glassEffect(.regular.tint(Theme.teal.opacity(0.18)), in: .capsule)
                } else if vm.hasFinishedActivity {
                    Label(model.t("activity.done.turn"), systemImage: "checkmark.circle.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.success)
                }
            }
            .padding(.horizontal, Space.m).padding(.bottom, Space.m).padding(.top, model.titlebarTopInset)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zoomWindowOnDoubleClick()
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    // When a recommendation is on screen over a team the user chose,
                    // make the choice explicit: selected vs recommended, and why. (Rare
                    // preview state — kept as its own card above the three groups.)
                    if isPreviewing, !vm.config.strategyIsAuto,
                       let rec = previewStrategy, rec.name != vm.config.strategy.name {
                        selectedVsRecommendedCard(recommended: rec).panelCard()
                    }
                    // Three grouped cards instead of ~9 loose ones (design review B3):
                    // Now → Team & output → Activity, each with quiet internal dividers.
                    nowCard.panelCard()
                    teamOutputCard.panelCard()
                    activityCard.panelCard()
                }
                .padding(Space.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same translucent surface as the chat + side columns, so the whole app shares
        // one glassy background. Structure comes from the inner .panelCard() surfaces.
        .translucentColumn()
        // Weekly / 5-hour usage figures for the live meter (Claude local logs).
        .task { if model.claudeUsage == nil { await model.refreshUsage() } }
    }

    // MARK: - Grouped cards (B3: ~9 loose cards → 3 with internal dividers)

    /// A quiet in-card separator between two grouped sections.
    private var sectionDivider: some View { Divider().padding(.vertical, 2) }

    /// "Now" — what's happening this turn: the live usage meter, the orchestrator +
    /// live topology, and the current task list.
    private var nowCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            liveUsageCard
            sectionDivider
            orchestratorDiagramCard
            if !vm.todos.isEmpty {
                sectionDivider
                tasksSection
            }
        }
    }

    /// "Team & output" — who's on the job, the files they produced, and the skills
    /// they pulled in.
    private var teamOutputCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            teamSection
            if !vm.editedFiles.isEmpty {
                sectionDivider
                filesSection
            }
            if !vm.skillsUsed.isEmpty {
                sectionDivider
                skillsSection
            }
        }
    }

    /// "Activity" — the live step timeline and (when idle) the reviewable history of
    /// past turns.
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            stepsSection
            if !vm.isRunning && !vm.history.isEmpty {
                sectionDivider
                historySection
            }
        }
    }

    /// Selected (what the user picked) vs Recommended (what the advisor suggests),
    /// side by side, with the one-line reason the recommendation may be better.
    private func selectedVsRecommendedCard(recommended: Strategy) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "arrow.triangle.swap").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.t("activity.compare.title"))
                    .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.6)
            }
            HStack(alignment: .top, spacing: Space.s) {
                compareColumn(tag: model.t("activity.compare.selected"), tint: Theme.teal,
                              name: model.strategyDisplayName(vm.config.strategy),
                              detail: model.t("activity.compare.roles", vm.config.strategy.roles.count))
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.top, 14)
                compareColumn(tag: (previewLabel ?? model.t("activity.compare.recommended")), tint: Theme.accent,
                              name: model.strategyDisplayName(recommended),
                              detail: model.t("activity.compare.roles", recommended.roles.count))
            }
            if let why = previewReason, !why.isEmpty {
                Text(model.t("activity.compare.why", why)).font(.sfCaption2)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compareColumn(tag: String, tint: Color, name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag.uppercased()).scaledFont(9, weight: .bold).foregroundStyle(tint).tracking(0.5)
            Text(name).font(.sfCaption2.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.sfCaption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(tint.opacity(0.08)))
    }

    // MARK: Orchestrator + diagram (merged card)

    /// The orchestrator status + the live topology, in one card (order: usage → this
    /// → team). The diagram stays collapsible via the header toggle.
    private var orchestratorDiagramCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            orchestratorContent
            Divider().padding(.vertical, 2)
            diagramContent
        }
    }

    private var orchestratorContent: some View {
        let subagent = vm.activeSubagent
        let modelName = shownStrategy.orchestrator?.modelDisplayName ?? "—"
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
                stat("person.2.fill", "\(shownStrategy.roles.count)")
                if let start = vm.turnStartedAt, vm.isRunning {
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        stat("clock", elapsed(from: start, to: ctx.date))
                    }
                }
                if vm.totalTokens > 0 { stat("circle.hexagongrid", (vm.costEstimated ? "~" : "") + formatTokens(vm.totalTokens)) }
                if vm.totalCostUSD > 0 { stat("dollarsign.circle", String(format: "\(vm.costEstimated ? "~" : "")$%.2f", vm.totalCostUSD)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The current objective/goal name: the in-progress task, else the chat title.
    private var goalText: String? {
        if let t = vm.todos.first(where: { $0.status == "in_progress" }), !t.content.isEmpty { return t.content }
        let name = vm.config.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The distinct models this run's team uses, with counts ("Opus 4.8 · Haiku 4.5 ×3").
    private func runModelSummary(_ s: Strategy) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for r in s.roles {
            let n = r.modelDisplayName
            if counts[n] == nil { order.append(n) }
            counts[n, default: 0] += max(1, r.count)
        }
        return order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: " · ")
    }

    /// The current chat's live tokens as a % of the 5-hour block and the week (from
    /// Claude's local usage), shown in parentheses next to the live token count.
    private func livePctSuffix() -> String? {
        guard let u = model.claudeUsage, vm.totalTokens > 0 else { return nil }
        var parts: [String] = []
        if u.blockTokens > 0 { parts.append(model.t("activity.usage.pct5h", pctStr(vm.totalTokens, u.blockTokens))) }
        if u.weekTokens > 0 { parts.append(model.t("activity.usage.pctWk", pctStr(vm.totalTokens, u.weekTokens))) }
        return parts.isEmpty ? nil : "(" + parts.joined(separator: " · ") + ")"
    }

    private func pctStr(_ part: Int, _ total: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = Double(part) / Double(total) * 100
        // A single chat is usually a tiny slice of the window, so show decimals when
        // it's small (0.013%) and round only once it's a meaningful chunk.
        if p >= 10 { return String(format: "%.0f%%", p) }
        if p >= 1 { return String(format: "%.1f%%", p) }
        if p >= 0.001 { return String(format: "%.3f%%", p) }
        return p > 0 ? "<0.001%" : "0%"
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).scaledFont(9)
            Text(text).font(.sfCaption2.weight(.medium))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: text)
        }
        .foregroundStyle(Theme.secondaryOnMaterial)
    }

    // MARK: Live usage (tokens + cost for the AIs in this chat)

    /// A live meter of this chat's token spend + cost, with the models in play — a
    /// quiet, pretty readout that ticks up during a run.
    private var liveUsageCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("activity.usage.title"))
                    .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Spacer()
                if vm.isRunning {
                    // A calm "live" badge — the working 3D mark already lives in the
                    // agent header above, so here it's just a small green dot + label.
                    HStack(spacing: 4) {
                        Circle().fill(Theme.teal).frame(width: 6, height: 6)
                        Text(model.t("activity.usage.live")).scaledFont(9, weight: .semibold)
                            .foregroundStyle(Theme.tealText)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.tealSoft))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                // Fixed on one line so a growing count never wraps ("53.2\nk").
                CountingNumber(value: Double(vm.totalTokens), format: formatTokens)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1).fixedSize()
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: vm.totalTokens)
                Text(model.t("activity.usage.tokens"))
                    .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                Spacer(minLength: Space.xs)
                if vm.totalCostUSD > 0 {
                    Text(String(format: "\(vm.costEstimated ? "~" : "")$%.2f", vm.totalCostUSD))
                        .font(.sfMono).foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: vm.totalCostUSD)
                        .help(vm.costEstimated ? model.t("usage.estimated.help") : "")
                }
            }
            // This chat's live tokens as a % of the 5-hour window + week — its own line
            // (never pushes the count into wrapping).
            if let pct = livePctSuffix() {
                Text(pct).font(.sfCaption2).foregroundStyle(Theme.tertiaryOnMaterial)
                    .contentTransition(.numericText())
            }
            // Liveness for the (silent) one-shot meta calls: a ticking elapsed so it's
            // obviously alive, and a "taking a while" nudge once it runs long — so a slow
            // provider reads as slow, not hung (and the user knows they can queue ahead).
            liveWorkingLine
            // Claude PLAN headroom (account-wide rate-limit %), so the "how much of my
            // plan is left" figure is visible here — not only on the Usage page.
            if let e = model.claudeExact {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle").scaledFont(9).foregroundStyle(.secondary)
                    Text(model.t("activity.usage.claudePlan",
                                 Int(e.fiveHourPercent.rounded()), Int(e.weekPercent.rounded())))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                }
            }
            // EXACT per-model / per-agent spend for THIS run (from each message's
            // own model), so e.g. Haiku subagent tokens show up. Falls back to the
            // team's configured models before any usage has streamed.
            if !vm.tokensByModel.isEmpty {
                runTokenBreakdown
            } else if !runModelSummary(shownStrategy).isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "cpu").scaledFont(9).foregroundStyle(Theme.tertiaryOnMaterial)
                    Text(runModelSummary(shownStrategy))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            // The account-wide totals (this week / 5-hour window / per-provider) live
            // in the Usage section — this live card shows ONLY this chat's own spend.
        }
    }

    /// A live "working · 2m 14s" line while a turn runs, with a "taking a while" nudge
    /// once it's been long — the liveness signal for the one-shot meta calls that don't
    /// stream tokens. Ticks once a second via a periodic TimelineView.
    @ViewBuilder private var liveWorkingLine: some View {
        if vm.isRunning, let started = (vm.roleStartedAt.values.min() ?? vm.turnStartedAt) {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                let secs = Int(max(0, ctx.date.timeIntervalSince(started)))
                HStack(spacing: 6) {
                    // ChatGPT-calm: no second blinking dot — the header already carries the
                    // single "alive" pulse.
                    Text(model.t("activity.working.elapsed", activityElapsed(from: started, to: ctx.date)))
                        .font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial)
                        .contentTransition(.numericText())
                    if secs >= 90 {
                        Text(model.t("activity.working.slow"))
                            .font(.sfCaption2).foregroundStyle(Theme.warningText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The cost tier (low/medium/high) of the shown/selected strategy.
    private var diagramCostPill: some View {
        let cost = CostEstimator.estimate(shownStrategy)
        let color: Color
        let key: String
        switch cost.tier {
        case .low:    color = Theme.success; key = "cost.tier.low"
        case .medium: color = Theme.warning; key = "cost.tier.medium"
        case .high:   color = Theme.danger;  key = "cost.tier.high"
        }
        return HStack(spacing: 3) {
            Image(systemName: "bolt.fill").scaledFont(8)
            Text(model.t(key)).scaledFont(9, weight: .semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: Diagram (collapsible, inside the merged card)

    /// The live topology — visible unless collapsed.
    private var diagramContent: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showDiagram.toggle() } } label: {
                HStack(spacing: Space.s) {
                    Text(model.t("activity.tab.diagram")).font(.sfFieldLabel)
                        .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                    diagramCostPill
                    Spacer()
                    Image(systemName: showDiagram ? "chevron.down" : "chevron.up")
                        .scaledFont(9, weight: .semibold).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDiagram {
                // While the team runs, the diagram becomes the SAME living object as the
                // inline conversation graph — orchestrator core fanning out to role-coloured
                // nodes. At rest it falls back to the static configured topology.
                if vm.isRunning {
                    LiveAgentGraphView(snapshot: vm.liveGraph)
                        .frame(height: 240)
                } else {
                    StrategyDiagramView(strategy: shownStrategy,
                                        activeAgent: vm.activeSubagent,
                                        isLive: vm.isRunning,
                                        compact: true)
                        .frame(height: 240)
                }
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
        (shownStrategy.orchestrator?.name).map(titleCase) ?? model.t("activity.orchestrator")
    }
    private var subagentNames: [String] {
        shownStrategy.subagentRoles.map { titleCase($0.name) }
    }

    enum AgentStatus { case active, done, idle }

    /// The whole team, listed from the start, each with its objective, live status
    /// and a filling progress bar (Claude-style).
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Collapsible header (collapsed by default) so the panel stays compact.
            Button { withAnimation(.easeInOut(duration: 0.15)) { showTeam.toggle() } } label: {
                HStack {
                    Text(model.t("activity.team")).font(.sfFieldLabel)
                        .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                    Text("\(shownStrategy.roles.count)")
                        .font(.sfCaption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.secondaryOnMaterial)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.hairline.opacity(0.6)))
                    Spacer()
                    Image(systemName: showTeam ? "chevron.up" : "chevron.down")
                        .scaledFont(9, weight: .semibold).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showTeam {
                agentRow(name: orchestratorName, icon: "brain.head.profile", target: .orchestrator,
                         objective: orchestratorObjective, status: orchestratorStatus)
                ForEach(shownStrategy.subagentRoles) { role in
                    let name = titleCase(role.name)
                    agentRow(name: name, icon: "person.fill", target: .sub(name),
                             objective: objective(forSubagent: name, fallback: role.description),
                             status: status(forSubagent: name))
                }
            }
        }
    }

    private var orchestratorObjective: String {
        let d = shownStrategy.orchestrator?.description ?? ""
        return d.isEmpty ? model.t("activity.orchestrator.role") : d
    }
    private var orchestratorStatus: AgentStatus {
        if vm.isRunning { return .active }
        return vm.hasFinishedActivity ? .done : .idle
    }
    private func status(forSubagent name: String) -> AgentStatus {
        // Prefer the per-role in-progress set (accurate when several workers run at once);
        // fall back to the single activeSubagent only when it's empty (native path). This
        // is what keeps the panel in lockstep with the chat — a finished worker no longer
        // shows "working" here while the chat shows it done.
        let active = vm.isRunning && (
            vm.rolesInProgress.contains { AgentNameMatcher.titlesMatch($0, name) }
            || (vm.rolesInProgress.isEmpty && AgentNameMatcher.titlesMatch(vm.activeSubagent ?? "", name))
        )
        if active { return .active }
        let hasWork = vm.timeline.contains { AgentNameMatcher.titlesMatch($0.agent ?? "", name) }
        return hasWork ? .done : .idle
    }

    /// What a role is ACTUALLY doing this turn (the orchestrator's assigned task) when
    /// known, else its generic role description — so the panel shows live intent.
    private func objective(forSubagent name: String, fallback: String) -> String {
        for (role, task) in vm.roleTasks where AgentNameMatcher.titlesMatch(role, name) {
            return task
        }
        return fallback
    }

    /// The tool steps attributed to one agent (Claude-Code-style per-agent metrics
    /// derived from the live timeline — the orchestrator owns the un-delegated steps).
    private func agentSteps(_ target: AgentFocus) -> [ActivityStep] {
        vm.timeline.filter { step in
            guard !step.isDelegation else { return false }
            switch target {
            case .orchestrator: return step.agent == nil
            case .sub(let n): return AgentNameMatcher.titlesMatch(step.agent ?? "", n)
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

    // MARK: Persistent agent history (#7)

    private var historySection: some View {
        DisclosureGroup(isExpanded: $showHistory) {
            VStack(alignment: .leading, spacing: Space.s) {
                // A/B the two most recent runs of this team — the test-bench move.
                if vm.history.count >= 2 {
                    Button {
                        showCompare = true
                    } label: {
                        Label(model.t("compare.lastTwo"), systemImage: "arrow.left.arrow.right.square")
                            .font(.sfCaption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                ForEach(vm.history.reversed()) { turn in historyTurnRow(turn) }
            }
            .padding(.top, Space.xs)
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.t("activity.history")).font(.sfFieldLabel)
                    .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Text("\(vm.history.count)").font(.sfCaption2.weight(.bold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Theme.accentSoft))
            }
        }
        .sheet(isPresented: $showCompare) {
            if vm.history.count >= 2 {
                RunCompareView(runA: vm.history[vm.history.count - 2],
                               runB: vm.history[vm.history.count - 1],
                               strategy: vm.config.strategy)
                    .environment(model)
            }
        }
    }

    private func historyTurnRow(_ turn: TurnActivity) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(turn.steps) { step in
                    ActivityStepRow(step: step, startedAt: turn.startedAt)
                }
            }
            .padding(.top, Space.xs)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("activity.history.turn", turn.turnIndex + 1))
                    .font(.sfCaption2.weight(.semibold))
                + Text("  \(turn.endedAt.formatted(.relative(presentation: .named)))")
                    .font(.sfCaption2).foregroundColor(.secondary)
                if !turn.prompt.isEmpty {
                    Text(turn.prompt).font(.sfCaption2).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.tail)
                }
                HStack(spacing: Space.s) {
                    Label("\(turn.steps.count)", systemImage: "list.bullet").scaledFont(9, weight: .medium)
                    if turn.tokensUsed > 0 {
                        Label(formatTokens(turn.tokensUsed), systemImage: "circle.hexagongrid").scaledFont(9, weight: .medium)
                    }
                    if turn.costUSD > 0 {
                        Text(String(format: "$%.2f", turn.costUSD)).scaledFont(9, design: .monospaced)
                    }
                }
                .foregroundStyle(Theme.tertiaryOnMaterial)
                if !turn.byModel.isEmpty {
                    Text(turn.byModel.map { "\(friendlyModelName($0.model)) \(formatTokens($0.tokens))" }
                        .joined(separator: " · "))
                        .scaledFont(9).foregroundStyle(Theme.secondaryOnMaterial)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    // MARK: This-run token breakdown (#8)

    /// Per-model spend this run (strongest model first) + per-agent when available.
    private var runTokenBreakdown: some View {
        let total = max(vm.tokensByModel.values.reduce(0, +), 1)
        let byModel = vm.tokensByModel.sorted {
            let ra = ClaudeUsageStore.powerRank($0.key), rb = ClaudeUsageStore.powerRank($1.key)
            return ra != rb ? ra < rb : $0.value > $1.value
        }
        let byAgent = vm.tokensByAgent.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 3) {
            Text(model.t("activity.usage.thisRun"))
                .scaledFont(9, weight: .semibold).foregroundStyle(Theme.tertiaryOnMaterial)
                .tracking(0.6)
            ForEach(byModel, id: \.key) { m in
                spendBar(label: friendlyModelName(m.key), tokens: m.value, total: total)
            }
            if !byAgent.isEmpty {
                ForEach(byAgent, id: \.key) { a in
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill").scaledFont(8).foregroundStyle(Theme.secondaryOnMaterial)
                        Text(a.key).scaledFont(9, weight: .medium).foregroundStyle(Theme.secondaryOnMaterial)
                        Spacer()
                        Text(pctOf(a.value, total)).scaledFont(9, design: .monospaced).foregroundStyle(Theme.tertiaryOnMaterial)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func spendBar(label: String, tokens: Int, total: Int) -> some View {
        let frac = Double(tokens) / Double(total)
        return VStack(spacing: 2) {
            HStack {
                Text(label).scaledFont(9, weight: .medium).foregroundStyle(Theme.secondaryOnMaterial)
                Spacer()
                // Each model's share of THIS chat, as a percentage (not raw tokens).
                Text(pctOf(tokens, total)).scaledFont(9, design: .monospaced).foregroundStyle(Theme.tertiaryOnMaterial)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline).frame(height: 4)
                    Capsule().fill(Theme.coral).frame(width: max(4, geo.size.width * frac), height: 4)   // your spend (data-viz) → bright coral, not teal/brick
                }
            }
            .frame(height: 4)
        }
    }

    /// A share as an integer percentage ("41%"), with one decimal for tiny slices.
    private func pctOf(_ part: Int, _ total: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = Double(part) / Double(total) * 100
        if p >= 1 { return String(format: "%.0f%%", p) }
        return p > 0 ? String(format: "%.1f%%", p) : "0%"
    }

    /// "claude-opus-4-8" → "Opus 4.8" (via ClaudeModel), else a tidied raw id.
    private func friendlyModelName(_ id: String) -> String {
        if let m = ClaudeModel(rawValue: id) { return m.displayName }
        return id.replacingOccurrences(of: "claude-", with: "").capitalized
    }

    // MARK: Files produced

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "doc.on.doc.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.t("activity.files.title"))
                    .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.6)
                Text("\(vm.editedFiles.count)")
                    .font(.sfCaption2.weight(.bold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.accentSoft))
                Spacer()
                Button { previewingFiles = true } label: {
                    Image(systemName: "eye").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .help(model.t("filepreview.title"))
            }
            // Newest first — the most recently produced file sits at the top.
            ForEach(Array(vm.editedFiles.reversed()), id: \.self) { path in fileRow(path) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $previewingFiles) { DocumentPreviewSheet(files: vm.editedFiles.reversed()) }
    }

    /// Which Agent Skills the model pulled into context this chat — so it's clear
    /// (in both normal and code chats) what playbooks were actually used.
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 11)).foregroundStyle(Theme.tealText)
                Text(model.t("activity.skills.title"))
                    .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.6)
                Text("\(vm.skillsUsed.count)")
                    .font(.sfCaption2.weight(.bold)).foregroundStyle(Theme.tealText)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.teal.opacity(0.14)))
                Spacer()
            }
            ForEach(vm.skillsUsed, id: \.self) { slug in
                HStack(spacing: Space.s) {
                    Image(systemName: "puzzlepiece.extension").font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryOnMaterial).frame(width: 16)
                    Text(slug).font(.sfCaption2).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3).padding(.horizontal, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileRow(_ path: String) -> some View {
        let name = (path as NSString).lastPathComponent
        return HStack(spacing: Space.s) {
            Image(systemName: fileIcon(name)).font(.system(size: 12))
                .foregroundStyle(Theme.secondaryOnMaterial).frame(width: 16)
            Text(name).font(.sfCaption2).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.xs)
            Button { downloadFile(path) } label: { Image(systemName: "arrow.down.circle").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .help(model.t("chat.download"))
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.secondaryOnMaterial)
            .help(model.t("activity.files.reveal"))
        }
        .padding(.vertical, 3).padding(.horizontal, Space.xs)
        .contentShape(Rectangle())
        .hoverTint(cornerRadius: 6)
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "pdf": return "photo"
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "sh": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    /// Save a copy of a produced file wherever the user chooses.
    private func downloadFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            model.flashSuccess(model.t("chat.fileSaved", url.lastPathComponent))
        } catch {
            model.flashFailure(error.localizedDescription)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("activity.steps")).font(.sfFieldLabel)
                    .foregroundStyle(Theme.tertiaryOnMaterial).tracking(0.8)
                Spacer()
                if !vm.timeline.isEmpty {
                    Button { focus = .allSteps } label: {
                        HStack(spacing: 2) {
                            Text(model.t("activity.seeAll")); Image(systemName: "chevron.right").scaledFont(8)
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
                        .foregroundStyle(status == .active ? Theme.teal : .secondary)
                        .frame(width: 16)
                    Text(name)
                        .font(.sfCaption2.weight(status == .active || isOpen ? .semibold : .medium))
                        .foregroundStyle(status == .idle ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    statusBadge(status)
                    Image(systemName: "chevron.right")
                        .scaledFont(9, weight: .semibold)
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
                            .scaledFont(9, weight: .medium)
                            .contentTransition(.numericText())
                        if let span = stats.span {
                            Label(span, systemImage: "clock")
                                .scaledFont(9, weight: .medium)
                        }
                    }
                    .foregroundStyle(Theme.tertiaryOnMaterial)
                    .padding(.leading, 16 + Space.s)
                }
                progressBar(status).padding(.leading, 16 + Space.s)
            }
            .padding(.horizontal, Space.s).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(status == .active ? Theme.tealSoft
                      : (isOpen ? Theme.accentSoft
                         : (hoveredAgent == target ? Theme.hairline.opacity(0.6) : .clear))))
            .overlay(alignment: .leading) {
                if status == .active {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.teal)
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
                Text(model.t("activity.running")).scaledFont(9, weight: .semibold)
            }
            .foregroundStyle(Theme.tealText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.tealSoft))
        case .done:
            Label(model.t("activity.done"), systemImage: "checkmark.circle.fill")
                .scaledFont(9, weight: .medium).foregroundStyle(Theme.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Theme.success.opacity(0.14)))
        case .idle:
            Label(model.t("activity.idle"), systemImage: "hourglass")
                .scaledFont(9, weight: .medium).foregroundStyle(Theme.secondaryOnMaterial)
        }
    }

    /// A filling bar per agent: animating while active, full when done, empty idle.
    @ViewBuilder
    private func progressBar(_ status: AgentStatus) -> some View {
        switch status {
        case .active:
            ProgressView().progressViewStyle(.linear).tint(Theme.teal)
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
                    : (todo.status == "in_progress" ? Theme.teal : Theme.secondaryOnMaterial.opacity(0.3))
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private func todoIcon(_ status: String) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case "in_progress": Image(systemName: "circle.dotted.circle").foregroundStyle(Theme.tealText)
        default: Image(systemName: "circle").foregroundStyle(Theme.tertiaryOnMaterial)
        }
    }

    // MARK: Helpers

    private func elapsed(from: Date, to: Date) -> String { activityElapsed(from: from, to: to) }
    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

/// A number that RAMPS smoothly to its target instead of snapping. The meta path
/// receives a whole agent's tokens at once, so the raw count jumps in big steps; this
/// interpolates through the intermediate values (Claude-style live counting).
struct CountingNumber: View, Animatable {
    var value: Double
    let format: (Int) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(Int(value.rounded()))) }
}

// MARK: - Panel section card (reference "Group Info" look)

private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.cardBg).elevation(.e1))   // lift off the column with ambient depth
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.4), lineWidth: 1))
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
                // A delegation is structure (a handoff), not a LIVE signal — the arrow +
                // indent + wash carry it; teal is freed for live-only (color review).
                .foregroundStyle(isActive ? Theme.success : .secondary)
                .frame(width: 16)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive && !step.isDelegation)
            Text(activityPhrase(step, model))
                .font(.sfCaption2.weight(step.isDelegation || isActive ? .semibold : .regular))
                .foregroundStyle(step.isDelegation ? AnyShapeStyle(.primary) : (isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
                .fixedSize(horizontal: false, vertical: true)
            // Which agent performed this step (subagents only; orchestrator is implicit).
            if let agent = step.agent, !agent.isEmpty, !step.isDelegation {
                Text(agent)
                    .scaledFont(9, weight: .semibold, design: .monospaced)
                    .foregroundStyle(Theme.tealText).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.tealSoft))
            }
            Spacer(minLength: Space.xs)
            if let start = startedAt {
                Text(activityElapsed(from: start, to: step.at))
                    .scaledFont(9, design: .monospaced).foregroundStyle(Theme.tertiaryOnMaterial)
            }
        }
        .padding(.vertical, step.isDelegation ? 6 : 2)
        .padding(.horizontal, step.isDelegation ? Space.s : 0)
        .background {
            if step.isDelegation {
                RoundedRectangle(cornerRadius: 8).fill(Theme.hairline.opacity(0.5))   // neutral handoff wash (teal = live only)
            } else if isActive {
                RoundedRectangle(cornerRadius: 8).fill(Theme.success.opacity(0.10))
            }
        }
        .overlay(alignment: .leading) {
            if step.isDelegation || isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(step.isDelegation ? AnyShapeStyle(Theme.secondaryOnMaterial) : AnyShapeStyle(Theme.success))
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
    // Meta path role markers — the detail holds the task (working) or role name (done).
    case "role.working": return target.isEmpty ? model.t("act.working") : model.t("act.workingOn", target)
    case "role.done": return model.t("act.roleDone", target.isEmpty ? "" : target)
    case "role.failed": return model.t("act.roleFailed", target.isEmpty ? "" : target)
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
        case .orchestrator: return vm.activeSubagent == nil && vm.rolesInProgress.isEmpty
        case .sub(let name):
            return vm.rolesInProgress.contains { AgentNameMatcher.titlesMatch($0, name) }
                || (vm.rolesInProgress.isEmpty && AgentNameMatcher.titlesMatch(vm.activeSubagent ?? "", name))
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
        // Same translucent surface as the rest of the app.
        .translucentColumn()
    }
}
