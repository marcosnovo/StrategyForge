//
//  AdvisorView.swift
//  StrategyForge
//
//  The Advisor section: paste the prompt you'd give an agent and get a local,
//  deterministic recommendation — model, team strategy, loop kind and effort —
//  with the decision path shown visually. Nothing is created until the user
//  clicks an action; the coordinator wires the two closures in ContentView.
//

import SwiftUI
import AppKit

struct AdvisorView: View {
    let onUseInChat: (AdvisorEngine.Advice, String) -> Void
    let onCreateLoop: (AdvisorEngine.Advice, String) -> Void

    @Environment(AppModel.self) private var model
    @State private var copiedCommand = false
    @State private var thinking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                hero
                promptCard
                if let advice = model.advisorAdvice {
                    // staggeredAppear cascades the cards on appear; the plain
                    // opacity transition just handles insertion into the layout.
                    resultsSection(advice)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 720)
            .padding(Space.xl)
            .frame(maxWidth: .infinity) // centers the column
        }
        // Static ambient wash — always mounted (never inserted/removed with an
        // animation; see the TimelineView-over-material note in ChatView).
        .background(AuroraBackground(intensity: 0.6))
        .background(Theme.appBg)
    }

    // MARK: - Header

    private var hero: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconBadge(systemName: "wand.and.stars")
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t("advisor.title")).font(.sfDisplay)
                Text(model.t("advisor.subtitle"))
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Prompt

    private var promptCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Space.m) {
            FieldLabel(text: model.t("advisor.prompt.label"))
            TextEditor(text: $model.advisorTask)
                .font(.sfBodyM)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
                .overlay(alignment: .topLeading) {
                    if model.advisorTask.isEmpty {
                        Text(model.t("advisor.placeholder"))
                            .font(.sfBodyM)
                            .foregroundStyle(.tertiary)
                            .padding(Space.s + 4)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Text(model.t("advisor.charCount", model.advisorTask.count))
                    .font(.sfCaption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    analyze()
                } label: {
                    if thinking {
                        HStack(spacing: Space.s) {
                            WorkingLogo(size: 15, color: Theme.onAccent)
                            Text(model.t("advisor.thinking"))
                        }
                    } else {
                        Label(model.t("advisor.analyze"), systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.moon)
                .disabled(thinking || model.advisorTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if StrategyGenerator.aiStatus != .available { aiUnavailableNote }
        }
        .card()
    }

    /// Shown when the on-device model can't shape the recommendation: explains the
    /// current source (local engine) and — when it's just off — offers to enable it.
    @ViewBuilder
    private var aiUnavailableNote: some View {
        let status = StrategyGenerator.aiStatus
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "cpu").font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("advisor.localOnly")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .notEnabled || status == .notReady {
                    Button(model.t("advisor.enableAI.full")) { openAppleIntelligenceSettings() }
                        .buttonStyle(.plain).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.warning.opacity(0.08)))
    }

    private func openAppleIntelligenceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preferences.AppleIntelligence",
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Recommend a setup. The deterministic pass is instant; when Apple Intelligence
    /// is available we additionally let the on-device model reshape the team (free,
    /// private) — hence the async path + a brief "thinking" state.
    private func analyze() {
        copiedCommand = false
        let task = model.advisorTask
        thinking = true
        Task {
            // Provider-aware: when >1 CLI is connected, mix providers per role;
            // otherwise this returns exactly the Claude-only advice.
            let advice = await AdvisorEngine.adviseCrossProvider(
                task: task, connected: model.connectedProviders)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                model.advisorAdvice = advice
            }
            thinking = false
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func resultsSection(_ advice: AdvisorEngine.Advice) -> some View {
        decisionCard(advice).staggeredAppear(index: 0)
        modelCard(advice).staggeredAppear(index: 1)
        strategyCard(advice).staggeredAppear(index: 2)
        if !advice.providerPicks.isEmpty {
            providersCard(advice).staggeredAppear(index: 3)
        }
        loopCard(advice).staggeredAppear(index: 4)
        actionsRow(advice).staggeredAppear(index: 5)
    }

    /// Cross-provider "why": one row per role showing the provider + model chosen and
    /// the reason (strong reasoning, best coder, widest context, diversity…). Only
    /// shown when >1 provider is connected and the engine actually mixed them.
    private func providersCard(_ advice: AdvisorEngine.Advice) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("square.stack.3d.up.fill", model.t("advisor.providers.title"))
            Text(model.t("advisor.providers.subtitle"))
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s) {
                ForEach(Array(advice.providerPicks.enumerated()), id: \.offset) { _, pick in
                    HStack(alignment: .center, spacing: Space.s) {
                        Image(systemName: pick.roleKind.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(pick.roleKind.tint)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(pick.roleKind.tint.opacity(0.16)))
                        Text(pick.roleName)
                            .font(.sfCallout.weight(.medium))
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)
                        ProviderAvatar(provider: pick.provider, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pick.modelDisplayName)
                                .font(.sfCallout.weight(.semibold))
                            Text(model.t(pick.reasonKey))
                                .font(.sfCaption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
        }
        .card()
    }

    private func decisionCard(_ advice: AdvisorEngine.Advice) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("arrow.triangle.branch", model.t("advisor.path.title"))
            DecisionPathView(steps: advice.decisionPath, terminal: advice.model.displayName)
        }
        .card()
    }

    @ViewBuilder
    private func modelCard(_ advice: AdvisorEngine.Advice) -> some View {
        let price = Constants.pricing[advice.model.rawValue]
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("cpu", model.t("advisor.model.title"))
            HStack(spacing: Space.m) {
                Image(systemName: advice.model.tierIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(advice.model.displayName).font(.sfDisplay)
                    Text(model.t(advice.model.tierNameKey))
                        .font(.sfCallout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let price {
                    Text(model.t("advisor.model.pricing", price.inputPerM, price.outputPerM))
                        .font(.sfCaption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let note = advice.model.safeguardNoteKey.map({ model.t($0) }) {
                Label(note, systemImage: "info.circle")
                    .font(.sfCaption2)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func strategyCard(_ advice: AdvisorEngine.Advice) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("person.3.fill", model.t("advisor.strategy.title")) {
                costPill(advice.estimatedCost)
            }
            StrategyDiagramView(strategy: advice.strategy, compact: true, ambient: false)
                .frame(height: 140)
            Text(model.strategyDisplayName(advice.strategy)).font(.sfCardTitle)
            Text(advice.aiRationale ?? model.t(advice.shapeRationaleKey))
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // A derived spec-sheet — the same legend skeleton as the loops explainer —
            // so it's unmistakable what this team is and when to use it.
            strategyLegend(advice.strategy)
            // Honest source label: Apple Intelligence vs the local deterministic engine.
            Label(model.t(advice.usedAI ? "advisor.source.ai.full" : "advisor.source.local.full"),
                  systemImage: advice.usedAI ? "sparkles" : "cpu")
                .font(.sfCaption2.weight(.medium))
                .foregroundStyle(advice.usedAI ? Theme.accent : .secondary)
        }
        .card()
    }

    /// Trigger / Rule / Best-for legend derived from the strategy's roles — mirrors
    /// the loops explainer so Chat and Code read as one system.
    private func strategyLegend(_ strategy: Strategy) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            legendRow(Theme.teal, model.t("loop.legend.trigger"), model.strategyTriggerLine(strategy))
            Divider()
            legendRow(Theme.warning, model.t("loop.legend.rule"), model.strategyTopologyLine(strategy))
            Divider()
            legendRow(Theme.success, model.t("loop.explain.bestFor").uppercased(), model.strategyGoodFor(strategy))
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private func legendRow(_ chip: Color, _ eyebrow: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            RoundedRectangle(cornerRadius: 2).fill(chip).frame(width: 10, height: 10).padding(.top, 2)
            Text(eyebrow).font(.sfFieldLabel).foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(text).font(.sfCaption2).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Same visual language as TeamView's cost pill, fed by the advice estimate.
    private func costPill(_ cost: StrategyCost) -> some View {
        let color: Color
        switch cost.tier {
        case .low: color = Theme.success
        case .medium: color = Theme.warning
        case .high: color = Theme.danger
        }
        return HStack(spacing: 5) {
            Image(systemName: "bolt.fill").font(.system(size: 9))
            Text(cost.headline)
                .font(.sfCaption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private func loopCard(_ advice: AdvisorEngine.Advice) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(advice.loopKind.icon, model.t("advisor.loop.title"))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t(advice.loopKind.labelKey)).font(.sfCardTitle)
                Text(model.t(advice.loopKind.blurbKey))
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // `flow` may be a literal or a key; t() passes unknown keys through.
                Text(model.t(advice.loopKind.flow))
                    .font(.sfFieldLabel)
                    .foregroundStyle(.tertiary)
            }
            FieldLabel(text: model.t("advisor.loop.goalLabel"))
            Text(advice.goalSuggestion)
                .font(.sfCode)
                .textSelection(.enabled)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
            // Why turning this into a loop improves broad-search / research results.
            Label(model.t("advisor.loop.whyResults"), systemImage: "arrow.triangle.2.circlepath")
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - Actions

    private func actionsRow(_ advice: AdvisorEngine.Advice) -> some View {
        HStack(spacing: Space.m) {
            Button {
                onUseInChat(advice, model.advisorTask)
            } label: {
                Label(model.t("advisor.action.chat"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .buttonStyle(.moon)
            .controlSize(.large)

            Button {
                onCreateLoop(advice, model.advisorTask)
            } label: {
                Label(model.t("advisor.action.loop"), systemImage: "arrow.triangle.2.circlepath")
            }

            Spacer()

            Button {
                copyLaunchCommand(advice)
            } label: {
                Label(model.t(copiedCommand ? "advisor.action.copied" : "advisor.action.copy"),
                      systemImage: copiedCommand ? "checkmark" : "terminal")
            }
            .buttonStyle(.plain)
            .font(.sfCaption2)
            .foregroundStyle(.secondary)
        }
    }

    private func copyLaunchCommand(_ advice: AdvisorEngine.Advice) {
        let command = LaunchCommandGenerator.command(for: advice.strategy)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation { copiedCommand = true }
    }
}
