//
//  LoopEditorView.swift
//  StrategyForge
//
//  The loop editor: one scroll of cards — kind → goal (with guardrails) →
//  worker/verifier team → cycle diagram → run panel — with a bottom action bar
//  (repo picker, preview, generate). Mirrors StrategyEditorView's structure.
//

import SwiftUI

struct LoopEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var plan: LoopPlan
    let store: LoopStore

    @State private var showPreview = false
    @State private var showGuardrails = false
    @State private var showKindDetails = false
    @State private var showKindPicker = false
    @State private var showAdvanced = false
    @State private var confirmDelete = false
    @State private var saveTask: Task<Void, Never>?

    private var repoURL: URL? { store.repoURL(for: plan) }
    private var intervalChoices: [Int] { [15, 30, 60, 120] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Minimal by default: to run a loop you only need a goal and a folder.
                // Everything else (type, team, guardrails, health) hides behind
                // "Customize", so the screen isn't a wall of config on first open.
                // Minimal, but the parts that explain the loop stay visible: the goal
                // (your task), the type + its animated diagram (how it works). Only the
                // deeper config (team, guardrails, health) hides behind "Customize".
                header
                runCard          // the hero: run it, with the folder right inside
                goalCard         // your task, as the loop's "done when"
                typeCard         // the type + its animated diagram, with "Change type"
                advancedToggle
                if showAdvanced {
                    teamCard
                    healthCard       // only meaningful after the loop has actually run
                    conditionsNudge  // a collapsed "is a loop worth it?" checklist
                }
                validationSummary
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .safeAreaInset(edge: .bottom, spacing: 0) { generateBar }
        .sheet(isPresented: $showPreview) { LoopFilePreviewSheet(plan: plan) }
        .confirmationDialog(model.t("loop.delete.confirm"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(model.t("loop.delete"), role: .destructive) { store.delete(plan.id) }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
        // Persist edits, coalesced so typing doesn't write the store per keystroke.
        .onChange(of: plan) {
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                store.save()
            }
        }
        .onDisappear { store.save() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(model.t("loop.editor.name.placeholder"), text: $plan.name)
                    .textFieldStyle(.plain)
                    .font(.sfDisplay)
                Text(model.t(plan.kind.labelKey))
                    .font(.sfCallout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(model.t("loop.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .glassPanel(cornerRadius: Theme.corner)
    }

    // MARK: - Health (cost per accepted change)

    /// The loop's running health — only once it has actually run. Surfaces the
    /// article's real success metric (cost per accepted change + accept rate) and
    /// warns when the accept rate has slipped below half.
    @ViewBuilder
    private var healthCard: some View {
        if let h = plan.health {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader("chart.line.uptrend.xyaxis", model.t("loop.health.title"),
                              subtitle: model.t("loop.health.subtitle"))
                HStack(alignment: .top, spacing: Space.xl) {
                    healthStat(model.t("loop.health.accepted"),
                               "\(h.accepted)/\(h.runs)",
                               detail: "\(Int((h.acceptanceRate * 100).rounded()))%",
                               tint: h.isUnderperforming ? Theme.warning : Theme.success)
                    if let cpa = h.costPerAccepted {
                        healthStat(model.t("loop.health.perAccepted"),
                                   String(format: "$%.2f", cpa), detail: nil, tint: Theme.ink)
                    }
                }
                if h.isUnderperforming {
                    Label(model.t("loop.health.warn"), systemImage: "exclamationmark.triangle.fill")
                        .font(.sfCallout).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func healthStat(_ label: String, _ value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.sfCaption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.sfCardTitle).foregroundStyle(tint)
                if let detail { Text(detail).font(.sfCallout).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: - "Is a loop worth it?" nudge

    /// A quiet, collapsed checklist of the four conditions that make a loop pay off —
    /// so a first-time builder frames the work before committing to the machinery.
    private var conditionsNudge: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.s) {
                conditionRow(model.t("loop.conditions.repeats"))
                conditionRow(model.t("loop.conditions.autoFail"))
                conditionRow(model.t("loop.conditions.budget"))
                conditionRow(model.t("loop.conditions.tools"))
                Text(model.t("loop.conditions.footnote"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s)
        } label: {
            Label(model.t("loop.conditions.title"), systemImage: "checklist")
                .font(.sfCardTitle)
        }
        .tint(Theme.accent)
        .card()
    }

    private func conditionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.sfCallout).foregroundStyle(Theme.success)
            Text(text).font(.sfCallout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tap reveals the loop's advanced config (type, team, guardrails, health) —
    /// hidden by default so the first thing a user sees is just "run this loop".
    private var advancedToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showAdvanced.toggle() }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "slider.horizontal.3").font(.sfCallout).foregroundStyle(Theme.accent)
                Text(model.t("loop.editor.customize")).font(.sfCallout.weight(.medium))
                Spacer()
                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .frame(maxWidth: .infinity)
            .glassPanel(cornerRadius: Theme.corner)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card · Type (name + animated diagram + change)

    /// The loop's type stays visible (with its animated diagram — that's what makes the
    /// mechanism click), but the 4-way picker + the spec-sheet legend only appear when
    /// you tap "Change type", so the default view is calm without hiding the explanation.
    private var typeCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("arrow.triangle.2.circlepath", model.t("loop.editor.kind.title"),
                              subtitle: model.t(plan.kind.blurbKey))
                Spacer(minLength: Space.s)
                Button(model.t(showKindPicker ? "common.done" : "loop.editor.changeType")) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showKindPicker.toggle() }
                }
                .buttonStyle(.plain).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
            }

            // The animated flow — always visible, so "how this type works" reads at a glance.
            LoopKindFlowDiagram(kind: plan.kind, maxTurns: plan.maxTurns,
                                intervalMinutes: plan.intervalMinutes)
                .frame(height: plan.kind == .proactive ? 160 : 140)
                .background(AuroraBackground(intensity: 0.35)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner)))

            // The picker + spec-sheet legend, revealed by "Change type".
            if showKindPicker {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                    GridItem(.flexible(), spacing: Space.m)],
                          spacing: Space.m) {
                    ForEach(LoopKind.allCases) { kind in kindCell(kind) }
                }
                DisclosureGroup(isExpanded: $showKindDetails) {
                    kindLegend.id(plan.kind).padding(.top, Space.s)
                } label: {
                    Text(model.t("loop.editor.kind.details")).font(.sfCallout.weight(.medium))
                }
                .tint(Theme.accent)
            }
        }
        .card()
    }

    /// The Start / Trigger / Rule / Stop legend (poster-style), color-coded so the
    /// eyebrow column reads as a stable key across all four loop types.
    private var kindLegend: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            legendRow(Theme.accent, model.t("loop.legend.start"), model.t(plan.kind.legendStartKey))
            Divider()
            legendRow(Theme.teal, model.t("loop.legend.trigger"), model.t(plan.kind.legendTriggerKey))
            Divider()
            legendRow(Theme.warning, model.t("loop.legend.rule"), model.t(plan.kind.legendRuleKey))
            Divider()
            legendRow(Theme.success, model.t("loop.legend.stop"), model.t(plan.kind.legendStopKey))
            Divider()
            // "Best for" — the when-to-pick answer, muted (no chip).
            legendRow(nil, model.t("loop.explain.bestFor").uppercased(), model.t(plan.kind.suitsKey),
                      glyph: "sparkles")
            cadenceFooter
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    /// One legend row: a color chip (or a muted glyph) + a mono-caps eyebrow in a
    /// fixed column + a one-sentence description.
    private func legendRow(_ chip: Color?, _ eyebrow: String, _ text: String,
                           glyph: String? = nil) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Group {
                if let chip {
                    RoundedRectangle(cornerRadius: 2).fill(chip).frame(width: 10, height: 10)
                } else if let glyph {
                    Image(systemName: glyph).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 12, alignment: .leading)
            .padding(.top, 2)
            Text(eyebrow).font(.sfFieldLabel).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(text).font(.sfCaption2).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The honest cadence for this type, using the plan's real maxTurns / interval.
    private var cadenceFooter: some View {
        let text: String
        switch plan.kind {
        case .turnBased: text = model.t("loop.cadence.turnBased")
        case .goalBased: text = model.t("loop.cadence.goalBased", plan.maxTurns)
        case .timeBased: text = model.t("loop.cadence.timeBased", plan.intervalMinutes)
        case .proactive: text = model.t("loop.cadence.proactive")
        }
        return HStack(spacing: 6) {
            Image(systemName: "gauge.with.needle").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(text).font(.sfCaption2).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func kindCell(_ kind: LoopKind) -> some View {
        let selected = plan.kind == kind
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { plan.kind = kind }
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    ZStack {
                        Circle().fill(Theme.accentSoft).frame(width: 30, height: 30)
                        Image(systemName: kind.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(model.t(kind.labelKey))
                        .font(.sfCallout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(model.t(kind.blurbKey))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(kind.flow)
                    .font(.sfFieldLabel)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? Theme.accentSoft : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? Theme.accent : Theme.hairline,
                              lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help(model.t(kind.suitsKey))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Card 2 · Goal + guardrails

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("target", model.t("loop.editor.goal.title"),
                          subtitle: model.t("loop.editor.goal.subtitle"))

            FieldLabel(text: model.t("loop.editor.goal.label"))
            textEditor($plan.goal, placeholder: model.t("loop.editor.goal.placeholder"), height: 76)

            // Good vs bad example, so "verifiable" is concrete.
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success).font(.system(size: 11))
                    Text(model.t("loop.editor.goal.good"))
                        .font(.sfCaption2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.danger).font(.system(size: 11))
                    Text(model.t("loop.editor.goal.bad"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))

            DisclosureGroup(isExpanded: $showGuardrails) {
                VStack(alignment: .leading, spacing: Space.m) {
                    FieldLabel(text: model.t("loop.editor.mustHold.label"))
                    textEditor($plan.mustHold,
                               placeholder: model.t("loop.editor.mustHold.placeholder"), height: 56)
                    Text(model.t("loop.editor.mustHold.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FieldLabel(text: model.t("loop.editor.neverTouch.label"))
                    textEditor($plan.neverTouch,
                               placeholder: model.t("loop.editor.neverTouch.placeholder"), height: 56)
                    FieldLabel(text: model.t("loop.editor.stopIf.label"))
                    textEditor($plan.stopIf,
                               placeholder: model.t("loop.editor.stopIf.placeholder"), height: 56)
                }
                .padding(.top, Space.s)
            } label: {
                Label(model.t("loop.editor.guardrails"), systemImage: "shield.lefthalf.filled")
                    .font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            HStack(spacing: Space.l) {
                Stepper(value: $plan.maxTurns, in: 1...100) {
                    Text(model.t("loop.editor.maxTurns", plan.maxTurns))
                        .font(.sfCallout).monospacedDigit()
                }
                .fixedSize()
                Text(model.t("loop.editor.maxTurns.brake"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            // The spend cap is the goal loop's second abort (beside the turn brake);
            // only that script tallies per-turn cost, so it's shown for goal loops.
            if plan.kind == .goalBased { budgetControl }

            if plan.kind == .timeBased {
                VStack(alignment: .leading, spacing: Space.xs) {
                    FieldLabel(text: model.t("loop.editor.interval"))
                    Picker("", selection: $plan.intervalMinutes) {
                        ForEach(intervalChoices, id: \.self) { m in
                            Text(model.t("loop.editor.minutes", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
        }
        .card()
    }

    /// A TextEditor with an inset border and a placeholder (TextEditor has none).
    private func textEditor(_ text: Binding<String>, placeholder: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11).padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Optional USD spend cap for a goal loop: a toggle that defaults to $5 when
    /// turned on, plus a stepper. `nil` budget = no cap emitted into loop.sh.
    private var budgetControl: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Toggle(isOn: Binding(
                get: { plan.budgetUSD != nil },
                set: { plan.budgetUSD = $0 ? (plan.budgetUSD ?? 5) : nil }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.budget")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.budget.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if plan.budgetUSD != nil {
                HStack(spacing: Space.s) {
                    Stepper(value: Binding(get: { plan.budgetUSD ?? 5 },
                                           set: { plan.budgetUSD = max(1, $0) }),
                            in: 1...1000, step: 1) {
                        Text(model.t("loop.editor.budget.amount")).font(.sfCaption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "$%.0f", plan.budgetUSD ?? 5))
                            .font(.sfCallout).monospacedDigit()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Card 3 · Team of the loop

    private var teamCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("person.2.fill", model.t("loop.editor.team.title"),
                          subtitle: model.t("loop.editor.team.subtitle"))

            FieldLabel(text: model.t("loop.editor.worker"))
            modelChips($plan.workerModel, enabled: true)

            FieldLabel(text: model.t("loop.editor.effort"))
            Picker("", selection: $plan.effort) {
                ForEach(CostEffort.allCases) { e in
                    Text(model.t(e.labelKey)).tag(e)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.t("loop.editor.effort.caption"))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(isOn: $plan.verifierEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.verifier")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.verifier.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            if plan.verifierEnabled {
                FieldLabel(text: model.t("loop.editor.verifier.model"))
                modelChips($plan.verifierModel, enabled: plan.verifierEnabled)
                // Surface the "reviewer ≠ author" guarantee as a quality seal.
                IndependentVerifierSeal(style: .full)
            }

            Divider()

            Toggle(isOn: $plan.memoryEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.memory")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.memory.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Toggle(isOn: $plan.useWorktree) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.worktree")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.worktree.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .card()
    }

    /// Model chips mirroring RoleEditorForm.modelGrid (tier icon + tier + name).
    private func modelChips(_ selection: Binding<ClaudeModel>, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(ClaudeModel.allCases) { m in
                let selected = selection.wrappedValue == m
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        selection.wrappedValue = m
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: m.tierIcon).font(.system(size: 12))
                            .foregroundStyle(selected ? Theme.accent : .secondary)
                        Text(model.t(m.tierNameKey))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? .primary : .secondary)
                            .lineLimit(1)
                        Text(m.displayName)
                            .scaledFont(8).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? Theme.accentSoft : Theme.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? Theme.accent : Theme.hairline,
                                      lineWidth: selected ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(m.safeguardNoteKey.map { model.t($0) } ?? model.t(m.tierBlurbKey))
                .accessibilityLabel("\(model.t(m.tierNameKey)) — \(m.displayName)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: - Card · Run panel (built by another module)

    private var runCard: some View {
        LoopRunPanel(plan: plan, repoURL: repoURL, binary: model.settings.claudeBinary, store: store)
    }

    // MARK: - Validation summary

    @ViewBuilder
    private var validationSummary: some View {
        let issues = plan.validate()
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(issues, id: \.self) { key in
                    let isWarning = key == "loop.issue.noVerifier" || key == "loop.issue.vagueGoal"
                    Label(model.t(key), systemImage: isWarning
                          ? "exclamationmark.triangle.fill" : "exclamationmark.octagon.fill")
                        .font(.sfCallout)
                        .foregroundStyle(isWarning ? Theme.warning : Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.warning.opacity(0.10)))
        }
    }

    // MARK: - Bottom action bar

    private var generateBar: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FieldLabel(text: model.t("preview.launch"))
            launchRow
            Text(model.t("loop.editor.launch.caption"))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if repoURL == nil {
                Text(model.t("loop.editor.needRepo"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Space.m) {
                Button {
                    store.pickRepo(for: plan.id)
                } label: {
                    Label(plan.repoPath.map { ($0 as NSString).lastPathComponent }
                          ?? model.t("loop.editor.chooseRepo"),
                          systemImage: "folder")
                }
                .buttonStyle(.reefOutline)
                .lineLimit(1)
                .help(model.t("loop.editor.chooseRepo.help"))

                if repoURL != nil {
                    Button {
                        revealRepo()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.reefOutline)
                    .help(model.t("loop.editor.reveal.help"))
                }

                Button {
                    showPreview = true
                } label: {
                    Label(model.t("loop.editor.preview"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.reefOutline)
                .lineLimit(1)

                Spacer(minLength: Space.s)

                Button {
                    generate()
                } label: {
                    Label(model.t("loop.editor.generate"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.moon)
                .disabled(repoURL == nil)
                .help(model.t("loop.editor.generate.help"))
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        // Frosted glass toolbar: a translucent material under a top sheen so the
        // aurora reads faintly through the bottom action bar.
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            LinearGradient(colors: [.white.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 24)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { Divider() }
    }

    /// The launch command, copyable — mirrors PreviewPanelView.launchBlock.
    private var launchRow: some View {
        let command = LoopFileGenerator.launchCommand(for: plan, binary: model.settings.claudeBinary)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(command.components(separatedBy: "\n").first ?? command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            CopyButton(text: command, help: model.t("loop.editor.copyLaunch"), flashKey: "banner.copied")
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.insetBg)
                .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .strokeBorder(Theme.hairline))
        )
    }

    // MARK: - Actions

    private func generate() {
        guard let url = repoURL else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let written = try LoopWriter(repoURL: url, binary: model.settings.claudeBinary)
                .write(plan: plan)
            model.flashSuccess(model.t("loop.editor.generated", written.count, url.lastPathComponent))
            store.save()
        } catch {
            model.flashFailure(model.t("loop.editor.generateFailed", error.localizedDescription))
        }
    }

    /// Reveal the loop's repo in Finder (security-scoped, mirroring generate()).
    private func revealRepo() {
        guard let url = repoURL else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - File preview sheet

/// A read-only preview of every file the loop would write, mirroring
/// FilePreviewSheet (segmented tabs + monospaced contents).
private struct LoopFilePreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: LoopPlan

    @State private var selectedFile: String?

    var body: some View {
        let files = LoopFileGenerator.generate(for: plan)
        let ids = files.map(\.id)
        let effective = (selectedFile.flatMap { ids.contains($0) ? $0 : nil }) ?? files.first?.id

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.t("loop.preview.title")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.l)
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { effective }, set: { selectedFile = $0 })) {
                    ForEach(files) { file in
                        Text(file.displayName).tag(Optional(file.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.l).padding(.top, Space.m)

                let current = files.first { $0.id == effective }
                ScrollView {
                    Text(current?.contents ?? "")
                        .font(.sfCode)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.l)
                }
                .background(Theme.insetBg)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
    }
}
