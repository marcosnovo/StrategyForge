//
//  TrajectoryCompareView.swift
//  StrategyForge
//
//  "What agent A knew vs what agent B redid" (Hanako, 2026). The duplicated work a team pays
//  for is invisible in the final answer and only shows in the TRAJECTORY. This lays each
//  agent's tool steps side by side and lights up the ones a teammate already did — so a
//  handoff that dropped the evidence (and made the next agent re-walk it) is visible at a
//  glance. Read-only; driven by the live timeline + the WastedWork detector.
//

import SwiftUI

struct TrajectoryCompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let steps: [ActivityStep]

    /// The set of (tool + target) keys that were done more than once (any agent) — the redone work.
    private var dupKeys: Set<String> {
        Set(WastedWork.detect(steps).map { $0.title + "\u{1}" + $0.detail })
    }
    private var redundant: Int { WastedWork.redundantCount(WastedWork.detect(steps)) }

    /// Tool steps grouped by the agent that ran them, in first-seen order.
    private var columns: [(agent: String, steps: [ActivityStep])] {
        var order: [String] = []
        var byAgent: [String: [ActivityStep]] = [:]
        for s in steps where isTool(s) {
            let a = (s.agent?.isEmpty ?? true) ? model.t("activity.orchestrator") : s.agent!
            if byAgent[a] == nil { byAgent[a] = []; order.append(a) }
            byAgent[a]!.append(s)
        }
        return order.map { ($0, byAgent[$0] ?? []) }
    }

    private func isTool(_ s: ActivityStep) -> Bool {
        !s.isDelegation && !s.title.hasPrefix("role.")
            && !(s.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(model.t("trajectory.title"), systemImage: "arrow.triangle.branch").font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m).background(Theme.chromeBg)

            if redundant > 0 {
                Label(model.t("trajectory.redone", redundant), systemImage: "arrow.triangle.2.circlepath")
                    .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.warning)
                    .padding(.horizontal, Space.l).padding(.top, Space.s)
            } else {
                Label(model.t("trajectory.clean"), systemImage: "checkmark.seal")
                    .font(.sfCaption2).foregroundStyle(Theme.success)
                    .padding(.horizontal, Space.l).padding(.top, Space.s)
            }

            if columns.isEmpty {
                Text(model.t("trajectory.empty")).font(.sfCaption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(columns, id: \.agent) { col in agentColumn(col.agent, col.steps) }
                    }
                    .padding(Space.l)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 860, minHeight: 420, idealHeight: 560)
        .background(Theme.appBg)
    }

    private func agentColumn(_ agent: String, _ steps: [ActivityStep]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 5) {
                Image(systemName: "person.fill").scaledFont(10).foregroundStyle(Theme.accent)
                Text(agent).font(.sfCaption2.weight(.semibold)).lineLimit(1)
                Text("\(steps.count)").font(.sfFieldLabel).foregroundStyle(.tertiary)
            }
            ForEach(steps) { s in
                let redone = dupKeys.contains(s.title + "\u{1}" + (s.detail ?? ""))
                HStack(spacing: Space.s) {
                    Image(systemName: activityToolIcon(s.title)).scaledFont(9)
                        .foregroundStyle(redone ? Theme.warning : .secondary).frame(width: 14)
                    Text("\(s.title) · \(s.detail ?? "")").font(.sfCaption2)
                        .foregroundStyle(redone ? Theme.warningText : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    if redone {
                        Text(model.t("trajectory.redone.tag")).scaledFont(8, weight: .bold)
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.warning.opacity(0.16)))
                    }
                }
                .padding(.horizontal, Space.s).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(redone ? Theme.warning.opacity(0.08) : .clear))
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline.opacity(0.4), lineWidth: 1))
    }
}
