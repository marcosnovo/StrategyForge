//
//  GraphLensSection.swift
//  StrategyForge
//
//  The node/edge cost lens, shown inside the strategy card's cost popover: what this team
//  actually pays for (nodes = model calls), what it moves for free (edges = data carried in
//  code), how wide the fan-out is, and what the straight-line version of the same work would
//  have cost. It makes "no markup" a number instead of a slogan.
//
//  Reads `GraphCostLens`, which prices the SAME `WorkflowShape` the generator emits — so if
//  a team compiles to a straight line, this says so out loud rather than flattering it.
//

import SwiftUI

struct GraphLensSection: View {
    @Environment(AppModel.self) private var model
    let strategy: Strategy
    let effort: CostEffort

    var body: some View {
        if let report = GraphCostLens.report(for: strategy, effort: effort) {
            VStack(alignment: .leading, spacing: Space.m) {
                Divider()
                FieldLabel(text: model.t("graphlens.title"))

                HStack(alignment: .top, spacing: Space.l) {
                    stat(model.t("graphlens.paid"), "\(report.nodes.count)",
                         detail: report.paidShort, tint: Theme.accent)
                    stat(model.t("graphlens.free"), "\(report.edgeCount)",
                         detail: "\(report.edgeTokens > 0 ? report.edgeShort : "$0.00") · \(model.t("graphlens.freeNote"))",
                         tint: Theme.success)
                }

                HStack(alignment: .top, spacing: Space.l) {
                    stat(model.t("graphlens.width"), "\(report.parallelWidth)",
                         detail: model.t("graphlens.path", report.criticalPath), tint: nil)
                    if report.isParallel, !report.savedPercentShort.isEmpty {
                        stat(model.t("graphlens.vsLine"), report.savedPercentShort,
                             detail: model.t("graphlens.saved", String(format: "$%.2f", report.savedUSD)),
                             tint: Theme.success)
                    }
                }

                if !report.isParallel {
                    Label(model.t("graphlens.straightLine"), systemImage: "arrow.right")
                        .font(.sfCaption2).foregroundStyle(Theme.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(model.t("graphlens.note"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ label: String, _ value: String, detail: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? Theme.ink)
            Text(detail).font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
