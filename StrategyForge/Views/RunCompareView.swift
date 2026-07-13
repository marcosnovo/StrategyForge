//
//  RunCompareView.swift
//  StrategyForge
//
//  Side-by-side diff of two finished runs of the same team — the A/B that turns the
//  run history into a test-bench. Baseline vs candidate: cost, tokens, steps, time,
//  and a per-agent breakdown, with cheaper/faster shown in green.
//

import SwiftUI

struct RunCompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let runA: TurnActivity   // baseline
    let runB: TurnActivity   // candidate
    let strategy: Strategy

    private var delta: RunAnalysis.RunDelta {
        RunAnalysis.compare(runA, runB, strategy: strategy)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.t("compare.title")).font(.sfCardTitle)
                    Text(model.t("compare.subtitle")).font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    metricsGrid
                    if !delta.agents.isEmpty { perAgentSection }
                }
                .padding(Space.l)
            }
        }
        .frame(width: 620, height: 560)
        .background(.regularMaterial)
        .bannerOverlay()
        .task { Analytics.log(.testbenchComparisonRun) }
    }

    // MARK: Metrics

    private var metricsGrid: some View {
        VStack(spacing: Space.s) {
            HStack {
                Spacer()
                Text(model.t("compare.runA")).font(.sfFieldLabel).foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                Text(model.t("compare.runB")).font(.sfFieldLabel).foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                Text("Δ").font(.sfFieldLabel).foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            metricRow(model.t("compare.metric.cost"),
                      a: fmtCost(delta.costA), b: fmtCost(delta.costB),
                      delta: signedCost(delta.costDelta), better: delta.costDelta < 0 ? .good : (delta.costDelta > 0 ? .bad : .neutral))
            metricRow(model.t("compare.metric.tokens"),
                      a: fmtTokens(delta.tokensA), b: fmtTokens(delta.tokensB),
                      delta: signedInt(delta.tokenDelta), better: delta.tokenDelta < 0 ? .good : (delta.tokenDelta > 0 ? .bad : .neutral))
            metricRow(model.t("compare.metric.steps"),
                      a: "\(delta.stepsA)", b: "\(delta.stepsB)",
                      delta: signedInt(delta.stepDelta), better: .neutral)
            metricRow(model.t("compare.metric.time"),
                      a: fmtSeconds(delta.secondsA), b: fmtSeconds(delta.secondsB),
                      delta: signedSeconds(delta.secondsDelta), better: delta.secondsDelta < 0 ? .good : (delta.secondsDelta > 0 ? .bad : .neutral))
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private enum Tone { case good, bad, neutral }

    private func metricRow(_ label: String, a: String, b: String, delta: String, better: Tone) -> some View {
        HStack {
            Text(label).font(.sfCallout.weight(.medium))
            Spacer()
            Text(a).font(.sfCode).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
            Text(b).font(.sfCode).frame(width: 110, alignment: .trailing)
            Text(delta).font(.sfCode.weight(.semibold))
                .foregroundStyle(color(better)).frame(width: 90, alignment: .trailing)
        }
    }

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .good: return Theme.success
        case .bad: return Theme.danger
        case .neutral: return .secondary
        }
    }

    // MARK: Per-agent

    private var perAgentSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("compare.perAgent")).font(.sfFieldLabel).foregroundStyle(.secondary).tracking(0.6)
            ForEach(delta.agents) { a in
                HStack {
                    Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(a.name).font(.sfCallout.weight(.medium))
                    Spacer()
                    Text("\(fmtTokens(a.tokensA)) → \(fmtTokens(a.tokensB))")
                        .font(.sfCode).foregroundStyle(.secondary)
                    Text(signedInt(a.tokensB - a.tokensA))
                        .font(.sfCode.weight(.semibold))
                        .foregroundStyle(color(a.tokensB < a.tokensA ? .good : (a.tokensB > a.tokensA ? .bad : .neutral)))
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    // MARK: Formatting

    private func fmtCost(_ c: Double) -> String { c > 0 ? String(format: "$%.2f", c) : "—" }
    private func signedCost(_ c: Double) -> String {
        if abs(c) < 0.005 { return model.t("compare.same") }
        return String(format: "%@$%.2f", c < 0 ? "−" : "+", abs(c))
    }
    private func signedInt(_ n: Int) -> String { n == 0 ? "—" : (n < 0 ? "−\(fmtTokens(-n))" : "+\(fmtTokens(n))") }
    private func signedSeconds(_ s: Double) -> String {
        if abs(s) < 1 { return model.t("compare.same") }
        return (s < 0 ? "−" : "+") + fmtSeconds(abs(s))
    }
    private func fmtSeconds(_ s: Double) -> String {
        let total = Int(s.rounded())
        if total <= 0 { return "—" }
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m \(total % 60)s"
    }
    private func fmtTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
