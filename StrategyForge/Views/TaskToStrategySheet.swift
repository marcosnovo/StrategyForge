//
//  TaskToStrategySheet.swift
//  StrategyForge
//
//  Beginner/power-user bridge: describe a task in plain language and get a
//  bespoke strategy (on-device via FoundationModels, heuristic fallback). The
//  result is always a real, validated library-derived Strategy — applying it is
//  the same as picking a template.
//

import SwiftUI

private struct TaskToStrategyPreviewHost: View {
    @State private var config = Configuration(name: "Demo", strategy: StrategyLibrary.executorAdvisor())
    var body: some View {
        TaskToStrategySheet(config: $config)
            .environment(AppModel())
            .tint(Theme.accent)
    }
}

#Preview("Task → Strategy") { TaskToStrategyPreviewHost() }
#Preview("Task → Strategy (Dark)") { TaskToStrategyPreviewHost().preferredColorScheme(.dark) }

struct TaskToStrategySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var config: Configuration

    @State private var task = ""
    @State private var isGenerating = false
    @State private var result: StrategyGenerator.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t("task2strat.title")).font(.sfDisplay)
                Text(model.t("task2strat.subtitle"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $task)
                .font(.sfBodyM)
                .frame(height: 110)
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
                .overlay(alignment: .topLeading) {
                    if task.isEmpty {
                        Text(model.t("task2strat.placeholder"))
                            .font(.sfBodyM).foregroundStyle(.tertiary)
                            .padding(Space.s + 4)
                            .allowsHitTesting(false)
                    }
                }

            if !StrategyGenerator.isAIAvailable {
                Label(model.t("task2strat.aiOff"), systemImage: "info.circle")
                    .font(.sfCaption2).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                generate()
            } label: {
                if isGenerating {
                    Label(model.t("task2strat.generating"), systemImage: "sparkles")
                } else {
                    Label(model.t("task2strat.generate"), systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)

            if let result {
                resultCard(result)
            }

            Spacer(minLength: 0)

            HStack {
                Button(model.t("common.cancel")) { dismiss() }
                Spacer()
                if let result {
                    Button {
                        model.applyTemplate(result.strategy, to: config.id)
                        dismiss()
                    } label: {
                        Label(model.t("task2strat.use"), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 560, height: 620)
        .background(Theme.appBg)
    }

    private func generate() {
        isGenerating = true
        let prompt = task
        Task {
            let r = await StrategyGenerator.generate(from: prompt)
            await MainActor.run {
                result = r
                isGenerating = false
            }
        }
    }

    private func resultCard(_ result: StrategyGenerator.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.strategyDisplayName(result.strategy)).font(.sfCardTitle).foregroundStyle(Theme.accent)
                Spacer()
                if result.usedAI {
                    Label("Apple Intelligence", systemImage: "sparkles")
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            if let rationale = result.aiRationale {
                Text(rationale).font(.sfCallout).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.strategyDisplayDescription(result.strategy))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StrategyDiagramView(strategy: result.strategy)
                .frame(height: StrategyDiagramView.preferredHeight(for: result.strategy))
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.cardBg)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1)))
    }
}
