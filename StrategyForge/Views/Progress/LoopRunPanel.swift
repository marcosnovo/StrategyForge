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
import AppKit

struct LoopRunPanel: View {
    let plan: LoopPlan
    let repoURL: URL?
    let binary: String
    let store: LoopStore
    @Environment(AppModel.self) private var model
    @State private var confirmRestore: LoopCheckpoint?
    @State private var scheduled = false
    @State private var lastScheduleError: String?
    @State private var authCheck: AuthCheck = .idle
    private enum AuthCheck: Equatable { case idle, checking, ok, failed }

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
        .card(padding: Space.m)
        .confirmationDialog(model.t("loop.checkpoint.restore.confirm"),
                            isPresented: Binding(get: { confirmRestore != nil },
                                                 set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button(model.t("loop.checkpoint.restore"), role: .destructive) {
                if let cp = confirmRestore { restore(cp) }
                confirmRestore = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { confirmRestore = nil }
        }
        .onAppear { scheduled = LoopScheduler.isScheduled(plan.id) }
    }

    /// Non-destructive rewind points captured after each iteration's work.
    @ViewBuilder
    private var checkpointsBlock: some View {
        if !controller.checkpoints.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                FieldLabel(text: model.t("loop.checkpoints"))
                ForEach(controller.checkpoints.reversed()) { cp in
                    HStack(spacing: Space.s) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10)).foregroundStyle(Theme.accent)
                        Text(model.t("loop.checkpoint.iteration", cp.iteration))
                            .font(.sfCaption2.weight(.medium))
                        Text(cp.at, format: .relative(presentation: .named))
                            .font(.sfCaption2).foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Button(model.t("loop.checkpoint.restore")) { confirmRestore = cp }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(controller.isRunning || repoURL == nil)
                    }
                }
            }
            .padding(.top, Space.xs)
        }
    }

    private func restore(_ cp: LoopCheckpoint) {
        guard let repoURL else { return }
        Task {
            let didAccess = repoURL.startAccessingSecurityScopedResource()
            defer { if didAccess { repoURL.stopAccessingSecurityScopedResource() } }
            let ok = await CodeGit.restore(repo: repoURL.path, sha: cp.sha)
            if ok { model.flashSuccess(model.t("loop.checkpoint.restored", cp.iteration)) }
            else { model.flashFailure(model.t("loop.checkpoint.restoreFailed")) }
        }
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
        VStack(alignment: .leading, spacing: Space.m) {
            // Launching needs exactly two things: a goal (usually pre-filled) and a
            // target folder. Surface BOTH here, in order, so nothing is hidden — the
            // folder picker used to live in a bar at the very bottom, which is why the
            // Run button read as "disabled for no reason".
            if goalEmpty {
                hint("target", model.t("progress.run.needsGoal"), color: Theme.warning)
            }
            folderRow
            Button { start() } label: {
                Label(model.t("progress.run.button"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.moon)
            .controlSize(.large)
            .disabled(!canRun)
            if plan.kind != .goalBased {
                hint("exclamationmark.triangle", model.t("progress.run.singlePass"),
                     color: Theme.warning)
            }
            scheduleRow
            if let last = plan.lastRun {
                lastRunBlock(last)
            }
        }
    }

    /// The one launch requirement made obvious and actionable, right next to Run: a big
    /// "choose a folder" button when none is set, a compact confirmation (with Change)
    /// once it is.
    @ViewBuilder
    private var folderRow: some View {
        if let repoURL {
            HStack(spacing: Space.s) {
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(repoURL.lastPathComponent).font(.sfCallout.weight(.medium)).lineLimit(1)
                Spacer(minLength: Space.s)
                Button(model.t("loop.editor.changeFolder")) { store.pickRepo(for: plan.id) }
                    .buttonStyle(.plain).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.insetBg))
        } else {
            Button { store.pickRepo(for: plan.id) } label: {
                Label(model.t("progress.run.chooseFolder"), systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.reefOutline)
            .controlSize(.large)
        }
    }

    /// Run this loop unattended on a cadence via a LaunchAgent (survives app close).
    @ViewBuilder
    private var scheduleRow: some View {
        if LoopScheduler.canSchedule(plan), repoURL != nil {
            VStack(alignment: .leading, spacing: Space.xs) {
                Toggle(isOn: Binding(get: { scheduled }, set: { setSchedule($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t("loop.schedule")).font(.sfCallout.weight(.medium))
                        Text(model.t("loop.schedule.every", plan.intervalMinutes))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                if scheduled {
                    hint("clock.badge.checkmark", model.t("loop.schedule.on"), color: Theme.success)
                    // Surface a silent background failure (e.g. an expired sign-in)
                    // by reading the last run's stderr, and let the user verify auth.
                    if lastScheduleError != nil {
                        hint("exclamationmark.triangle.fill", model.t("loop.schedule.lastError"),
                             color: Theme.warning)
                    }
                    HStack(spacing: Space.s) {
                        verifyButton
                        if lastScheduleError != nil {
                            Button(model.t("loop.schedule.viewLog")) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: LoopScheduler.errLogPath(for: plan.id)))
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            .padding(.top, Space.xs)
            .onAppear { lastScheduleError = LoopScheduler.lastErrorLog(for: plan.id) }
        }
    }

    /// One-shot auth health check — the honest way to tell if a scheduled run would
    /// fail because the provider sign-in has expired.
    @ViewBuilder
    private var verifyButton: some View {
        Button { verifySignIn() } label: {
            switch authCheck {
            case .checking:
                HStack(spacing: 6) { WorkingLogo(size: 13); Text(model.t("loop.schedule.verifying")) }
            case .ok:
                Label(model.t("loop.schedule.signedIn"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            case .failed:
                Label(model.t("loop.schedule.signInExpired"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            case .idle:
                Text(model.t("loop.schedule.verify"))
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(authCheck == .checking)
    }

    private func verifySignIn() {
        authCheck = .checking
        let runner = CLIOneShotRunner(binaries: [.claude: binary])
        let modelID = AIProvider.claude.models.first?.id ?? plan.workerModel.rawValue
        Task {
            do {
                _ = try await runner.run(prompt: "Reply with OK.", provider: .claude,
                                         model: modelID, cwd: repoURL?.path)
                authCheck = .ok
            } catch {
                authCheck = .failed
            }
        }
    }

    private func setSchedule(_ on: Bool) {
        if on {
            guard let repoURL else { return }
            Task {
                let didAccess = repoURL.startAccessingSecurityScopedResource()
                defer { if didAccess { repoURL.stopAccessingSecurityScopedResource() } }
                // resolveBinary + launchctl run off the main actor (login shell is slow).
                let err = LoopScheduler.enable(plan: plan, repoURL: repoURL,
                                               binary: binary, intervalMinutes: plan.intervalMinutes)
                await MainActor.run {
                    if let err { model.flashFailure(err); scheduled = false }
                    else {
                        scheduled = true
                        lastScheduleError = nil
                        model.flashSuccess(model.t("loop.schedule.enabled", plan.intervalMinutes))
                    }
                }
            }
        } else {
            Task {
                LoopScheduler.disable(plan.id)
                await MainActor.run {
                    scheduled = false
                    model.flashSuccess(model.t("loop.schedule.disabled"))
                }
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
            checkpointsBlock
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
            checkpointsBlock
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
