//
//  LoopRunPanel.swift
//  StrategyForge
//
//  The "run this loop" card embedded by the Loop editor: a Run button when idle,
//  the shared loop-progress visual + live status while running, and the verdict
//  with usage once finished. Executes the loop locally via LoopRunController.
//
//  NOTE for the embedding view: apply `.id(plan.id)` at the call site so switching
//  to another loop re-creates this panel (and its controller) — a run always
//  belongs to exactly one plan.
//

import SwiftUI

struct LoopRunPanel: View {
    let plan: LoopPlan
    let repoURL: URL?
    let binary: String
    @Environment(AppModel.self) private var model
    @State private var controller = LoopRunController()

    private var goalEmpty: Bool {
        plan.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canRun: Bool { repoURL != nil && !goalEmpty }
    private var finished: Bool {
        !controller.isRunning && (controller.stage == .done || controller.stage == .failed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if controller.isRunning {
                runningBody
            } else if finished {
                finishedBody
            } else {
                idleBody
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(model.t("progress.run.title")).font(.sfCallout.weight(.semibold))
            InfoPopoverButton(text: model.t("progress.run.info"))
            Spacer(minLength: 0)
        }
    }

    // MARK: Idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { start() } label: {
                Label(model.t("progress.run.button"), systemImage: "play.fill")
            }
            .buttonStyle(.moon)
            .disabled(!canRun)
            if repoURL == nil {
                hint("folder.badge.questionmark", model.t("progress.run.needsRepo"))
            } else if goalEmpty {
                hint("target", model.t("progress.run.needsGoal"))
            }
            if plan.kind != .goalBased {
                hint("exclamationmark.triangle", model.t("progress.run.singlePass"),
                     color: Theme.warning)
            }
        }
    }

    private func hint(_ icon: String, _ text: String, color: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.sfCaption2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }

    // MARK: Running

    private var runningBody: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LoopProgressView(iteration: controller.iteration,
                             maxTurns: controller.maxTurns,
                             stage: controller.stage,
                             verdicts: controller.verdicts)
            HStack(spacing: Space.s) {
                Text(model.t(controller.statusKey))
                    .font(.sfCaption2.weight(.medium)).foregroundStyle(.primary)
                    .fixedSize()
                if !controller.liveDetail.isEmpty {
                    Text(controller.liveDetail)
                        .font(.sfCaption2).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(spacing: Space.m) {
                if let start = controller.startedAt {
                    // Same 1s elapsed ticker as AgentActivityPanel's status card.
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        statCaption("clock", activityElapsed(from: start, to: ctx.date))
                    }
                }
                usageCaptions
                Spacer(minLength: Space.s)
                Button { controller.stop() } label: {
                    Label(model.t("progress.run.stop"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: Finished

    private var finishedBody: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LoopProgressView(iteration: controller.iteration,
                             maxTurns: controller.maxTurns,
                             stage: controller.stage,
                             verdicts: controller.verdicts)
            if let reason = controller.lastVerdictReason, !reason.isEmpty {
                Text(reason)
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.m) {
                usageCaptions
                Spacer(minLength: Space.s)
                Button { start() } label: {
                    Label(model.t("progress.run.again"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.moon).controlSize(.small)
                .disabled(!canRun)
            }
        }
    }

    // MARK: Shared bits

    @ViewBuilder
    private var usageCaptions: some View {
        if controller.totalTokens > 0 {
            statCaption("circle.hexagongrid",
                        model.t("progress.run.tokens", formatTokens(controller.totalTokens)))
        }
        if controller.totalCostUSD > 0 {
            statCaption("dollarsign.circle", String(format: "$%.2f", controller.totalCostUSD))
        }
    }

    private func statCaption(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.sfCaption2.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func start() {
        guard let repoURL else { return }
        // The work/verifier prompts tell the model to read LOOP.md (and STATE.md),
        // so make sure the loop files exist and are current before launching —
        // quietly, mirroring how chats write their strategy files before a run.
        let didAccess = repoURL.startAccessingSecurityScopedResource()
        defer { if didAccess { repoURL.stopAccessingSecurityScopedResource() } }
        _ = try? LoopWriter(repoURL: repoURL, binary: binary).write(plan: plan)
        controller.start(plan: plan, repoURL: repoURL, binary: binary)
    }
}
