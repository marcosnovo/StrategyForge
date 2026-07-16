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
    /// How the grid is ordered (persisted). "Recommended" is the library's own order.
    @AppStorage("picker.sortRank") private var sortRankRaw = StrategyRank.recommended.rawValue
    private var sortRank: StrategyRank { StrategyRank(rawValue: sortRankRaw) ?? .recommended }
    /// Strategy whose generated files are being previewed (context menu).
    @State private var previewStrategy: Strategy?
    /// True once the one-shot entrance cascade has finished (see the grid).
    @State private var introPlayed = false

    /// The templates in the chosen order (cheapest / fastest / smartest / best value …).
    private var templates: [Strategy] { StrategyRanking.sorted(StrategyLibrary.all, by: sortRank) }

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

            sortPills
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
        // One uniform translucent surface (same as the chat + panels) — no aurora
        // gradient behind the strategy grid.
        .translucentColumn()
        .sheet(isPresented: $showWizard) {
            if let config { ChooseStrategyWizard(config: config) }
        }
        .sheet(isPresented: $showTaskGen) {
            if let config { TaskToStrategySheet(config: config) }
        }
        .sheet(item: $previewStrategy) { s in
            FilePreviewSheet(config: Configuration(name: s.name, strategy: s))
        }
    }

    /// Topic pills that orient the list by everyday goal. Tapping filters (reorders
    /// + dims) and stars the recommended strategy — it never changes the selection.
    /// Order the grid by the dimension the user cares about (cost / speed / smarts /
    /// value). A labelled row of single-select action pills.
    private var sortPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                Text(model.t("picker.sortBy").uppercased())
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6).padding(.trailing, 1)
                ForEach(StrategyRank.allCases) { rank in
                    let on = sortRank == rank
                    Button { sortRankRaw = rank.rawValue } label: {
                        Label(model.t(rank.labelKey), systemImage: rank.icon)
                            .font(.sfCaption2.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .background(Capsule().fill(on ? Theme.accent : Theme.hairline.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .help(model.t(rank.labelKey))
                }
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.bottom, Space.xs)
    }

    /// Narrow the grid to strategies suited to an everyday GOAL (a soft lens, not a hard
    /// filter — tapping the active pill clears it). Labelled so it's clear what it does.
    private var topicPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                Text(model.t("picker.filterBy").uppercased())
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6).padding(.trailing, 1)
                // An explicit "All" chip to clear the goal filter.
                let allOn = activeBucket == nil
                Button { activeBucket = nil } label: {
                    Text(model.t("picker.all"))
                        .font(.sfCaption2.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(allOn ? Theme.onAccent : Theme.ink)
                        .background(Capsule().fill(allOn ? Theme.accent : Theme.hairline.opacity(0.55)))
                }
                .buttonStyle(.plain)
                ForEach(AppModel.TopicBucket.allCases) { bucket in
                    let on = activeBucket == bucket
                    Button {
                        activeBucket = on ? nil : bucket
                    } label: {
                        Label(model.t(bucket.labelKey), systemImage: bucket.icon)
                            .font(.sfCaption2.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .background(Capsule().fill(on ? Theme.accent : Theme.hairline.opacity(0.55)))
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
        // Show the team as it would ACTUALLY run given what's connected: the same
        // cross-provider assignment the advisor/chat applies, so the diagram, cost and
        // provider summary reflect Claude / ChatGPT-Codex / Gemini — not a fixed 100%
        // Claude template. (No-op when only Claude is connected.)
        let displayed = AdvisorEngine.assignProviders(to: template, connected: model.connectedProviders).strategy
        return Button {
            onSelect(displayed)
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                // Static topology per card. `ambient: false` stops every card in the
                // grid running a 20fps clock (a wall of pickers was burning CPU redrawing
                // idle thumbnails); the live chat diagram still animates.
                // The card is a fixed size (below), but the diagram FILLS the space left
                // above the text — so its boxes get as tall as the card allows instead of
                // sitting small in a 120pt slot with empty room beneath.
                StrategyDiagramView(strategy: displayed, compact: true, ambient: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 5) {
                    Text(model.strategyDisplayName(template))
                        .font(.sfCallout.weight(.semibold))
                        .foregroundStyle(selected ? Theme.accent : .primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                // What SHAPE is this team — answered at a glance, derived from roles.
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                    Text(model.strategyTopologyLine(template))
                        .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                let goodFor = model.strategyGoodFor(template)
                if !goodFor.isEmpty {
                    Text("\(model.t("picker.bestfor")): \(goodFor)")
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                // Chips row: topology tag + cost, then a compact summary of the AI
                // providers the team uses, on the far right (right of the cost).
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
                    costTierPill(displayed)
                    Spacer(minLength: 4)
                    providerSummary(displayed)
                }
            }
            .padding(Space.m)
            // Every card is the same fixed size (uniform grid), content top-aligned.
            .frame(maxWidth: .infinity, minHeight: 312, maxHeight: 312, alignment: .topLeading)
            .contentShape(Rectangle())
            .selectedRow(selected, cornerRadius: Theme.innerCorner, restingFill: Theme.cardBg)
            // Keep the resting card hairline when unselected; selection draws its own.
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help(model.strategyDisplayName(template))
        .contextMenu {
            Button(model.t("picker.previewFiles")) { previewStrategy = template }
        }
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

    /// The distinct AI providers this strategy's roles use, in catalog order.
    private func providers(_ s: Strategy) -> [AIProvider] {
        let used = Set(s.roles.map(\.provider))
        return AIProvider.allCases.filter { used.contains($0) }
    }

    /// A compact cluster of the team's provider logos — the "who runs this" summary at
    /// the card's bottom-right, next to the cost.
    private func providerSummary(_ template: Strategy) -> some View {
        HStack(spacing: -5) {
            ForEach(providers(template)) { p in
                ProviderAvatar(provider: p, size: 18)
            }
        }
        .help(providers(template).map(\.displayName).joined(separator: " · "))
    }
}
