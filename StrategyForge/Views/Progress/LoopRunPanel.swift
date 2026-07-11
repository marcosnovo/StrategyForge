//
//  LoopRunPanel.swift
//  StrategyForge
//
//  The "run this loop" card embedded by the Loop editor: a Run button when idle,
//  the shared loop-progress visual + live status while running, and the verdict
//  with usage once finished. Executes the loop locally via the store-owned
//  LoopRunController, so a run keeps going when the panel goes off-screen.
//

import SwiftUI

struct LoopRunPanel: View {
    let plan: LoopPlan
    let repoURL: URL?
    let binary: String
    let store: LoopStore
    @Environment(AppModel.self) private var model

    /// The store-owned controller for this plan. Lazy creation mutates only an
    /// @ObservationIgnored dict on the store — safe in body.
    private var controller: LoopRunController { store.runController(for: plan.id) }

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
            if let last = plan.lastRun {
                lastRunBlock(last)
            }
        }
    }

    /// Persisted outcome of the most recent run, shown while idle.
    private func lastRunBlock(_ last: LoopRunSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            FieldLabel(text: model.t("loop.lastRun"))
            HStack(spacing: Space.s) {
                lastRunVerdict(last)
                Text(last.date, format: .relative(presentation: .named))
                    .font(.sfCaption2).foregroundStyle(.tertiary)
            }
            if let reason = last.reason, !reason.isEmpty {
                Text(reason)
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: Space.m) {
                if last.tokens > 0 {
                    statCaption("circle.hexagongrid",
                                model.t("progress.run.tokens", formatTokens(last.tokens)))
                }
                if last.costUSD > 0 {
                    statCaption("dollarsign.circle", String(format: "$%.2f", last.costUSD))
                }
            }
        }
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private func lastRunVerdict(_ last: LoopRunSummary) -> some View {
        switch last.pass {
        case .some(true):
            Text(model.t("progress.verdict.pass"))
                .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.success)
        case .some(false):
            Text(model.t("progress.verdict.fail"))
                .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.danger)
        case .none:
            Text(model.t("progress.status.doneUnverified"))
                .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
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
        do {
            _ = try LoopWriter(repoURL: repoURL, binary: binary).write(plan: plan)
        } catch {
            // Don't start a run whose charter files couldn't be written.
            model.flashFailure(model.t("loop.editor.generateFailed", error.localizedDescription))
            return
        }
        controller.start(plan: plan, repoURL: repoURL, binary: binary)
    }
}
