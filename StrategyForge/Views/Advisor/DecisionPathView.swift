//
//  DecisionPathView.swift
//  StrategyForge
//
//  The visual decision path: a vertical chain of question → answer rows joined
//  by a coral connector, ending in the recommendation capsule — a native take on
//  Anthropic's "which model should I use" flowchart. Pure presentation: all the
//  reasoning lives in AdvisorEngine.
//

import SwiftUI

struct DecisionPathView: View {
    let steps: [AdvisorEngine.DecisionStep]
    /// Optional terminal recommendation (e.g. the model's display name) rendered
    /// as the final coral capsule. Defaults to nil so `DecisionPathView(steps:)`
    /// stays a valid call.
    var terminal: String? = nil

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                stepRow(step)
                if index < steps.count - 1 || terminal != nil {
                    connector
                }
            }
            if let terminal {
                terminalRow(terminal)
            }
        }
    }

    // MARK: - Rows

    private func stepRow(_ step: AdvisorEngine.DecisionStep) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // The question, in an inset bubble.
            Text(model.t(step.questionKey))
                .font(.sfCallout)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                // Translucent glass pill for the question (airy Aetheris chip).
                .glassPanel(cornerRadius: 999)
                .fixedSize(horizontal: false, vertical: true)

            // The answer taken, with its YES/NO chip.
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                answerChip(step.answerIsYes)
                Text(model.t(step.answerKey))
                    .font(.sfCallout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Space.m)

            // Which signals actually fired (dimmed, small).
            if !step.evidenceKeys.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(step.evidenceKeys, id: \.self) { key in
                        Text("· " + model.t(key))
                            .font(.sfCaption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, Space.m + 40)
            }
        }
    }

    private func answerChip(_ yes: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: yes ? "checkmark" : "xmark")
                .scaledFont(8, weight: .bold)
            Text(model.t(yes ? "advisor.chip.yes" : "advisor.chip.no").uppercased())
                .font(.sfFieldLabel)
        }
        .foregroundStyle(Theme.success)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.success.opacity(0.16)))
    }

    /// A 2pt coral line with a subtle arrowhead, linking consecutive steps.
    private var connector: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.coral)
                .frame(width: 2, height: 16)
            Image(systemName: "arrowtriangle.down.fill")
                .scaledFont(7)
                .foregroundStyle(Theme.coral)
        }
        .padding(.leading, Space.l)
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    /// Terminal row: the recommendation in a coral-tinted capsule.
    private func terminalRow(_ name: String) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                FieldLabel(text: model.t("advisor.path.result"))
                Text(name)
                    .font(.sfMono)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(Capsule().fill(Theme.accentSoft))
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}
