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
    @Binding var config: Configuration
    @State private var showWizard = false
    @State private var showTaskGen = false

    private var templates: [Strategy] { StrategyLibrary.all }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + guided picker entry.
            VStack(alignment: .leading, spacing: Space.s) {
                Text(model.t("picker.header"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Button { showTaskGen = true } label: {
                    Label(model.t("task2strat.open"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
            .padding(Space.m)

            Divider()

            ScrollView {
                VStack(spacing: Space.xs) {
                    ForEach(templates) { template in
                        strategyRow(template)
                    }
                }
                .padding(Space.m)
                .animation(.easeInOut(duration: 0.15), value: config.strategy.name)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.appBg)
        .sheet(isPresented: $showWizard) {
            ChooseStrategyWizard(config: $config)
        }
        .sheet(isPresented: $showTaskGen) {
            TaskToStrategySheet(config: $config)
        }
    }

    /// A selectable strategy row: mini-diagram thumbnail + name + cost-tier pill.
    private func strategyRow(_ template: Strategy) -> some View {
        let selected = template.name == config.strategy.name
        let beginner = model.isBeginnerStrategy(template)
        return Button {
            model.applyTemplate(template, to: config.id)
        } label: {
            HStack(spacing: Space.m) {
                StrategyThumbnail(strategy: template)
                    .frame(width: 60, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(model.strategyDisplayName(template))
                            .font(.sfCallout.weight(.medium))
                            .foregroundStyle(selected ? Theme.accent : .primary)
                            .lineLimit(1)
                        if beginner {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 8)).foregroundStyle(Theme.success)
                        }
                    }
                    costTierPill(template)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? Theme.accentSoft : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? Theme.accent : Theme.hairline,
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .help(model.strategyDisplayName(template))
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
