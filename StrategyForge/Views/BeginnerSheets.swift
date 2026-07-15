//
//  BeginnerSheets.swift
//  StrategyForge
//
//  Two beginner-facing sheets:
//   • ChooseStrategyWizard — one or two plain questions → a recommended strategy.
//   • WhatNowSheet — shown right after generating, explaining how to launch it.
//

import SwiftUI
import AppKit

// MARK: - Help-me-choose wizard

struct ChooseStrategyWizard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var config: Configuration

    private enum Goal { case build, understand, bulk, play }
    private enum Care { case simple, careful }

    @State private var goal: Goal?
    @State private var care: Care?

    // The strategy implied by the current answers, if enough is known.
    private var suggestion: Strategy? {
        switch goal {
        case .understand: return StrategyLibrary.researchFanout()
        case .bulk: return StrategyLibrary.orchestratorWorkers()
        case .play: return StrategyLibrary.solo()
        case .build:
            switch care {
            case .simple: return StrategyLibrary.executorAdvisor()
            case .careful: return StrategyLibrary.plannerImplementersReviewer()
            case .none: return nil
            }
        case .none: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t("wizard.title")).font(.sfDisplay)
                Text(model.t("wizard.subtitle")).font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    question(model.t("wizard.q1"), options: [
                        (model.t("wizard.q1.build"), goal == .build, { goal = .build; care = nil }),
                        (model.t("wizard.q1.understand"), goal == .understand, { goal = .understand; care = nil }),
                        (model.t("wizard.q1.bulk"), goal == .bulk, { goal = .bulk; care = nil }),
                        (model.t("wizard.q1.play"), goal == .play, { goal = .play; care = nil }),
                    ])

                    if goal == .build {
                        question(model.t("wizard.q2"), options: [
                            (model.t("wizard.q2.simple"), care == .simple, { care = .simple }),
                            (model.t("wizard.q2.careful"), care == .careful, { care = .careful }),
                        ])
                    }

                    if let suggestion {
                        resultCard(suggestion)
                    }
                }
                .padding(.vertical, Space.xs)
            }

            HStack {
                Button(model.t("common.cancel")) { dismiss() }
                Spacer()
                if let suggestion {
                    Button {
                        model.applyTemplate(suggestion, to: config.id)
                        dismiss()
                    } label: {
                        Label(model.t("wizard.apply"), systemImage: "checkmark")
                    }
                    .buttonStyle(.moon)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520, height: 560)
        .background(Theme.appBg)
    }

    private typealias Option = (label: String, selected: Bool, action: () -> Void)

    private func question(_ title: String, options: [Option]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.sfCardTitle)
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button(action: opt.action) {
                    HStack(spacing: Space.m) {
                        Image(systemName: opt.selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(opt.selected ? Theme.accent : Color.secondary)
                        Text(opt.label).font(.sfBodyM).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                            .fill(opt.selected ? Theme.accentSoft : Theme.cardBg)
                            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                                .strokeBorder(opt.selected ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resultCard(_ strategy: Strategy) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FieldLabel(text: model.t("wizard.result"))
            Text(model.strategyDisplayName(strategy)).font(.sfDisplay).foregroundStyle(Theme.accent)
            Text(model.strategyDisplayDescription(strategy))
                .font(.sfCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StrategyDiagramView(strategy: strategy)
                .frame(height: StrategyDiagramView.preferredHeight(for: strategy))
        }
        // Rounded floating result card with soft depth.
        .card(padding: Space.l)
    }
}

// MARK: - "What now?" post-generate sheet

struct WhatNowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let config: Configuration

    @State private var showExplain = false

    private var launchCommand: String {
        LaunchCommandGenerator.command(for: config.strategy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(Theme.success)
                Text(model.t("whatnow.title")).font(.sfDisplay)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(model.t("whatnow.lead")).font(.sfCardTitle)

            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    StepBadge(number: 1)
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(model.t("whatnow.step1")).font(.sfBodyM)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            model.generateAndOpenTerminal(config)
                            dismiss()
                        } label: {
                            Label(model.t("whatnow.step1.button"), systemImage: "terminal")
                        }
                        .buttonStyle(.moon)
                    }
                }

                HStack(alignment: .top, spacing: Space.m) {
                    StepBadge(number: 2)
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(model.t("whatnow.step2")).font(.sfBodyM)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.s) {
                            Text(launchCommand)
                                .font(.sfCode)
                                .padding(Space.s)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
                                .textSelection(.enabled)
                            CopyButton(text: launchCommand,
                                       help: model.t("preview.copy.help"),
                                       flashKey: "banner.copied")
                        }
                    }
                }
            }
            // Rounded floating steps card with soft depth.
            .card(padding: Space.l)

            DisclosureGroup(isExpanded: $showExplain) {
                Text(model.t("whatnow.explain.body"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s)
            } label: {
                Text(model.t("whatnow.explain.toggle")).font(.sfCallout.weight(.medium))
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    model.revealGeneratedFiles(config)
                } label: {
                    Label(model.t("whatnow.showFiles"), systemImage: "folder")
                }
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .buttonStyle(.moon)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 560, height: 560)
        .background(Theme.appBg)
        // Sheets cover the window's banner host — give this one its own.
        .bannerOverlay()
    }
}
