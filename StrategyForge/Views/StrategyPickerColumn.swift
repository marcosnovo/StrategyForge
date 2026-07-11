//
//  StrategyPickerColumn.swift
//  StrategyForge
//
//  The middle column of the three-pane layout: pick the strategy here (a vertical
//  list of thumbnails), while the left column holds saved configurations and the
//  right column holds the fine configuration + download of the selected strategy.
//

import SwiftUI

struct StrategyPickerColumn: View {
    @Environment(AppModel.self) private var model
    /// Optional chat binding — present when picking a strategy for a chat (enables
    /// the guided wizard/task-gen sheets). nil in "create a team" mode.
    var config: Binding<Configuration>?
    /// The strategy name to mark as selected (for the checkmark/highlight).
    var selectedStrategyName: String?
    /// Invoked when a strategy card is chosen.
    var onSelect: (Strategy) -> Void

    @State private var showWizard = false
    @State private var showTaskGen = false
    @State private var activeBucket: AppModel.TopicBucket?
    /// True once the one-shot entrance cascade has finished (see the grid).
    @State private var introPlayed = false

    private var templates: [Strategy] { StrategyLibrary.all }

    /// Entrance stagger, first showing only — afterwards the raw view, so
    /// filter-driven ForEach rebuilds don't blank and re-cascade the grid.
    @ViewBuilder
    private func introStaggered(_ view: some View, index: Int) -> some View {
        if introPlayed { view } else { view.staggeredAppear(index: index) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + guided picker entry.
            VStack(alignment: .leading, spacing: Space.s) {
                Text(model.t("picker.header"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                // The guided generators write into a chat's config, so they only
                // appear when picking for a chat — not in "create a team" mode.
                if config != nil {
                    Button { showTaskGen = true } label: {
                        Label(model.t("task2strat.open"), systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.moon)
                    .controlSize(.small)
                    .help(model.t("task2strat.subtitle"))

                    Button { showWizard = true } label: {
                        Label(model.t("wizard.open"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(model.t("wizard.help"))
                }
            }
            .padding(Space.m)

            topicPills

            Divider()

            // Spacious, scannable grid of strategies — the protagonist of this pane.
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 360), spacing: Space.m)],
                          alignment: .leading, spacing: Space.m) {
                    if let bucket = activeBucket {
                        let inBucket = templates.filter { model.strategyBuckets($0).contains(bucket) }
                        let others = templates.filter { !model.strategyBuckets($0).contains(bucket) }
                        ForEach(Array(inBucket.enumerated()), id: \.element.id) { index, template in
                            introStaggered(strategyCard(template), index: index)
                        }
                        ForEach(Array(others.enumerated()), id: \.element.id) { index, template in
                            introStaggered(strategyCard(template).opacity(0.5),
                                           index: inBucket.count + index)
                        }
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            introStaggered(strategyCard(template), index: index)
                        }
                    }
                }
                .padding(Space.l)
                .animation(.easeInOut(duration: 0.15), value: selectedStrategyName)
                .animation(.easeInOut(duration: 0.15), value: activeBucket)
                // The entrance cascade plays once, on the column's first showing.
                // Afterwards the flag strips the modifier entirely, so topic-pill
                // taps (which rebuild the ForEach branches and would reset the
                // stagger state) just reorder/dim smoothly instead of blanking
                // and re-cascading the whole grid.
                .task {
                    try? await Task.sleep(for: .seconds(1.1))   // > max delay + spring
                    introPlayed = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Static ambient wash — always mounted (never inserted/removed with an
        // animation; see the TimelineView-over-material note in ChatView).
        .background(AuroraBackground(intensity: 0.5))
        .background(Theme.appBg)
        .sheet(isPresented: $showWizard) {
            if let config { ChooseStrategyWizard(config: config) }
        }
        .sheet(isPresented: $showTaskGen) {
            if let config { TaskToStrategySheet(config: config) }
        }
    }

    /// Topic pills that orient the list by everyday goal. Tapping filters (reorders
    /// + dims) and stars the recommended strategy — it never changes the selection.
    private var topicPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(AppModel.TopicBucket.allCases) { bucket in
                    let on = activeBucket == bucket
                    Button {
                        activeBucket = on ? nil : bucket
                    } label: {
                        Label(model.t(bucket.labelKey), systemImage: bucket.icon)
                            .font(.sfCaption2.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(on ? Theme.onAccent : .secondary)
                            .background(Capsule().fill(on ? Theme.accent : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.bottom, Space.s)
    }

    /// A tall, scannable strategy card: topology on top, then name, best-for and the
    /// task/cost chips — big enough to read in the wide grid.
    private func strategyCard(_ template: Strategy) -> some View {
        let selected = template.name == selectedStrategyName
        return Button {
            onSelect(template)
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                // Ambient signal-dot motion on every card — the diagram's identity,
                // matching the live chat diagram. Compact mode collapses multi-count
                // roles into one stacked card and the layout caps node height to the
                // slot, so the topology stays legible and the grid drifts at 20fps.
                StrategyDiagramView(strategy: template, compact: true)
                    .frame(height: StrategyDiagramView.compactHeight(for: template))
                HStack(spacing: 5) {
                    Text(model.strategyDisplayName(template))
                        .font(.sfCallout.weight(.semibold))
                        .foregroundStyle(selected ? Theme.accent : .primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                let goodFor = model.strategyGoodFor(template)
                if !goodFor.isEmpty {
                    Text("\(model.t("picker.bestfor")): \(goodFor)")
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    if let bucket = activeBucket, model.isRecommended(template, for: bucket) {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text(model.t("picker.recommended")).font(.sfCaption2.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accentSoft))
                    }
                    taskTagChip(template)
                    costTierPill(template)
                    Spacer(minLength: 0)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? Theme.accentSoft : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help(model.strategyDisplayName(template))
    }

    /// Neutral "what task" chip — deliberately NOT colored so it reads as a
    /// different axis from the (green/amber/red) cost pill beside it.
    @ViewBuilder
    private func taskTagChip(_ template: Strategy) -> some View {
        let tag = model.strategyTaskTag(template)
        if !tag.isEmpty {
            Text(tag)
                .font(.sfCaption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Theme.hairline))
        }
    }

    private func costTierPill(_ template: Strategy) -> some View {
        let cost = CostEstimator.estimate(template)
        let color: Color
        let label: String
        switch cost.tier {
        case .low: color = Theme.success; label = model.t("cost.tier.low")
        case .medium: color = Theme.warning; label = model.t("cost.tier.medium")
        case .high: color = Theme.danger; label = model.t("cost.tier.high")
        }
        return HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.system(size: 8))
            Text(label).font(.sfCaption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}
