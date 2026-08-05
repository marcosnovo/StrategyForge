//
//  EvalsView.swift
//  StrategyForge
//
//  Evals card for a team: generate a scenario suite, run the team against it scored by
//  the independent read-only judge, and show a pass-rate + gate + per-scenario verdicts.
//  Addresses Karpathy's flagged gap (evals, not just observability).
//

import SwiftUI

struct EvalsView: View {
    @Environment(AppModel.self) private var model
    @Binding var strategy: Strategy

    @State private var run: EvalRun?
    @State private var regression: EvalRegression?
    @State private var isBusy = false
    @State private var progress: (done: Int, total: Int)?
    // Auto-improve (RAI) — derive probes from usage, run, edit one lever, repeat.
    @State private var improving = false
    @State private var improveLog: [String] = []
    @State private var improveOutcome: ImproveOutcome?
    @State private var showImprove = false

    private var suite: EvalSuite { strategy.evalSuite ?? EvalSuite() }
    private var scenarios: [EvalScenario] { suite.scenarios }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("checklist.checked", model.t("eval.title"), subtitle: model.t("eval.subtitle"))
            IndependentVerifierSeal(style: .full)   // same independent judge grades the evals

            if scenarios.isEmpty {
                Text(model.t("eval.empty"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                summaryRow
                if run != nil { thresholdCaption }
                if let reg = regression, reg.hasBaseline { regressionRow(reg) }
                ForEach(scenarios) { scenario in scenarioRow(scenario, run: run) }
            }

            actions
            if let p = progress, isBusy {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text(model.t("eval.progress", p.done, p.total)).font(.sfCaption2).foregroundStyle(.secondary)
            } else if isBusy {
                // Generating scenarios (single CLI call, no per-item progress) — a self-timing
                // "working… Xs" line so it never looks frozen.
                WorkingLine(label: model.t("eval.generating"))
            }
            if improving, let last = improveLog.last {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text(last).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .card()
        .sheet(isPresented: $showImprove) { improveSheet }
    }

    // MARK: Summary + gate

    private var summaryRow: some View {
        HStack(spacing: Space.s) {
            Text(model.t("eval.count", scenarios.count)).font(.sfCaption2).foregroundStyle(.secondary)
            Spacer()
            if let run {
                let ok = run.meetsThreshold
                Label(model.t(ok ? "eval.ready" : "eval.notReady"),
                      systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.sfCaption2.weight(.semibold))
                    .foregroundStyle(ok ? Theme.success : Theme.warning)
                Text("\(run.passed)/\(run.total) · \(Int((run.passRate * 100).rounded()))%")
                    .font(.sfMono).foregroundStyle(.primary)
            }
        }
    }

    private var thresholdCaption: some View {
        Text(model.t("eval.threshold", Int((suite.passThreshold * 100).rounded())))
            .font(.sfCaption2).foregroundStyle(.tertiary)
    }

    /// Regression vs the suite's saved baseline: what broke / got fixed since last run (#6).
    private func regressionRow(_ reg: EvalRegression) -> some View {
        HStack(spacing: Space.s) {
            if reg.regressed.isEmpty && reg.fixed.isEmpty {
                Label(model.t("eval.noRegression"), systemImage: "equal.circle")
                    .font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                if !reg.regressed.isEmpty {
                    Label(model.t("eval.regressed", reg.regressed.count), systemImage: "arrow.down.right.circle.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.danger)
                }
                if !reg.fixed.isEmpty {
                    Label(model.t("eval.fixed", reg.fixed.count), systemImage: "arrow.up.right.circle.fill")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.success)
                }
                Text(model.t("eval.regression.since")).font(.sfFieldLabel).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private func scenarioRow(_ scenario: EvalScenario, run: EvalRun?) -> some View {
        let result = run?.results.first { $0.scenarioID == scenario.id }
        return HStack(alignment: .top, spacing: Space.s) {
            // Verdict marker: pass = green circle, fail = red square (colorblind-safe),
            // unrun = hollow. Uses the EFFECTIVE verdict (a human override wins).
            Group {
                if let r = result {
                    if r.effectivePassed {
                        Circle().fill(Theme.success)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.danger)
                    }
                } else {
                    Circle().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .frame(width: 9, height: 9).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.prompt).font(.sfCaption2).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: Space.xs) {
                    Text(model.t(scenario.category.labelKey)).font(.sfFieldLabel).foregroundStyle(.tertiary)
                    // Trajectory verdict (#4): whether the PATH matched, when graded.
                    if let tp = result?.trajectoryPassed {
                        Label(model.t(tp ? "eval.path.ok" : "eval.path.bad"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .labelStyle(.titleOnly).font(.sfFieldLabel)
                            .foregroundStyle(tp ? Theme.success : Theme.danger)
                            .help(model.t("eval.path.help"))
                    }
                    if result?.humanVerdict != nil {
                        Text(model.t("eval.overridden")).font(.sfFieldLabel).foregroundStyle(Theme.accent)
                    }
                }
                // Per-dimension rubric scores (#3), when the judge returned them.
                if let scores = result?.scores, !scores.isEmpty { rubricLine(scores) }
                if let r = result, !r.effectivePassed, !r.reason.isEmpty {
                    Text(r.reason).font(.sfCaption2).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            // Judge calibration (#8): agree / disagree, so a drifting judge can be caught.
            if let r = result { calibrateButtons(for: r) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scenario.prompt)
        .accessibilityValue(result.map { $0.effectivePassed ? model.t("eval.pass") : "\(model.t("eval.fail")): \($0.reason)" } ?? "")
    }

    /// "correctness 4 · grounding 3 · safety 5" in the rubric's dimension order.
    private func rubricLine(_ scores: [String: Int]) -> some View {
        let ordered = EvalRunner.rubricDimensions.filter { scores[$0] != nil }
            + scores.keys.filter { !EvalRunner.rubricDimensions.contains($0) }.sorted()
        return Text(ordered.map { "\(model.t("eval.dim.\($0)")) \(scores[$0]!)" }.joined(separator: " · "))
            .font(.sfFieldLabel).foregroundStyle(.secondary)
    }

    private func calibrateButtons(for result: EvalResult) -> some View {
        HStack(spacing: 2) {
            let agree = result.humanVerdict == result.passed && result.humanVerdict != nil
            let disagree = result.humanVerdict != nil && result.humanVerdict != result.passed
            Button { setHuman(result.scenarioID, result.passed) } label: {
                Image(systemName: agree ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.plain).foregroundStyle(agree ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.tertiary))
            .help(model.t("eval.calibrate.agree"))
            Button { setHuman(result.scenarioID, !result.passed) } label: {
                Image(systemName: disagree ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .buttonStyle(.plain).foregroundStyle(disagree ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.tertiary))
            .help(model.t("eval.calibrate.disagree"))
        }
        .font(.system(size: 11))
    }

    /// Record the human's verdict for a scenario, updating the gate live.
    private func setHuman(_ scenarioID: UUID, _ verdict: Bool) {
        guard var out = run, let i = out.results.firstIndex(where: { $0.scenarioID == scenarioID }) else { return }
        // Toggle off if they tap the same verdict they already set.
        out.results[i].humanVerdict = (out.results[i].humanVerdict == verdict) ? nil : verdict
        run = out
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Space.s) {
            Button {
                Task { await generate() }
            } label: {
                Label(model.t(scenarios.isEmpty ? "eval.generate" : "eval.regenerate"),
                      systemImage: "sparkles")
            }
            .buttonStyle(.bordered).disabled(isBusy)

            if !scenarios.isEmpty {
                Button {
                    Task { await runEvals() }
                } label: {
                    Label(model.t("eval.run"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).disabled(isBusy)
            }

            Spacer()
            // RAI: derive probes (from real usage), run, edit one lever, repeat until they
            // pass — the team self-heals toward its own spec, judged independently.
            Button {
                Task { await autoImprove() }
            } label: {
                Label(model.t("eval.improve"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered).disabled(isBusy || improving)
            .help(model.t("eval.improve.help"))
        }
    }

    // MARK: Drive the engine

    private func generate() async {
        isBusy = true; defer { isBusy = false }
        let scenarios = await EvalRunner.generate(team: strategy, count: 12,
                                                  runner: model.oneShotRunner(readOnly: false))
        guard !scenarios.isEmpty else { model.flashFailure(model.t("eval.generateFailed")); return }
        var s = strategy.evalSuite ?? EvalSuite()
        s.scenarios = scenarios
        s.baseline = [:]   // new scenarios have new ids — the old baseline no longer applies
        strategy.evalSuite = s
        run = nil; regression = nil   // stale results no longer match the new scenarios
        model.flashSuccess(model.t("eval.generated", scenarios.count))
    }

    private func runEvals() async {
        isBusy = true; progress = (0, scenarios.count)
        defer { isBusy = false; progress = nil }
        let outcome = await EvalRunner.run(
            team: strategy, suite: suite, cwd: nil,
            answerRunner: model.oneShotRunner(readOnly: false),
            judgeRunner: model.oneShotRunner(readOnly: true)) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
        // Regression vs the saved baseline BEFORE we overwrite it (#6).
        regression = EvalRegression.between(baseline: suite.baseline, run: outcome)
        run = outcome
        // Persist this run as the new baseline for next time.
        var s = strategy.evalSuite ?? EvalSuite()
        s.baseline = outcome.baselineMap
        strategy.evalSuite = s
        model.flashSuccess(model.t("eval.doneBanner", outcome.passed, outcome.total))
    }

    // MARK: Auto-improve (RAI)

    /// Recent user prompts this exact team was actually given — the usage the probes are
    /// mined from (the article's key move). Best-effort across all chats on this strategy.
    private func usageExcerpts() -> [String] {
        model.configurations
            .filter { $0.strategy.name == strategy.name }
            .flatMap { $0.transcript }
            .filter { $0.role == .user }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(30)
            .reversed()
    }

    private func autoImprove() async {
        improving = true; improveLog = []; improveOutcome = nil
        defer { improving = false }
        let outcome = await TeamImprover.improve(
            team: strategy, usageExcerpts: usageExcerpts(), maxIterations: 5,
            answerRunner: model.oneShotRunner(readOnly: false),
            judgeRunner: model.oneShotRunner(readOnly: true)) { event in
                Task { @MainActor in
                    switch event {
                    case .status(let s): improveLog.append(s)
                    case .probes(let n): improveLog.append(model.t("eval.improve.probes", n))
                    case .scoring(let round, let done, let total):
                        // Live per-probe progress so it never looks frozen mid-run. Replace the
                        // last line when it's already a scoring line for this round.
                        let line = model.t("eval.improve.scoring", round, done, total)
                        if let last = improveLog.last, last.hasPrefix("⏱") { improveLog[improveLog.count - 1] = "⏱ " + line }
                        else { improveLog.append("⏱ " + line) }
                    case .iteration(let i, let passed, let total):
                        improveLog.append(model.t("eval.improve.round", i, passed, total))
                    case .applied(let edit): improveLog.append("✏️ \(edit.roleName): \(edit.rationale)")
                    case .finished(let rate, let iters):
                        improveLog.append(model.t("eval.improve.finished", Int((rate * 100).rounded()), iters))
                    case .failed(let m): improveLog.append("⚠️ \(m)")
                    }
                }
            }
        guard let outcome else { model.flashFailure(model.t("eval.improve.failed")); return }
        improveOutcome = outcome
        showImprove = true
    }

    /// Review the proposed edits (start→end pass rate + one line per lever changed) and
    /// APPLY them to the team, or discard. Convergent, human-in-the-loop by construction.
    @ViewBuilder private var improveSheet: some View {
        if let outcome = improveOutcome {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(model.t("eval.improve.title"), systemImage: "wand.and.stars").font(.sfCardTitle)
                    Spacer()
                    Text("\(Int((outcome.startPassRate * 100).rounded()))% → \(Int((outcome.endPassRate * 100).rounded()))%")
                        .font(.sfMono)
                        .foregroundStyle(outcome.endPassRate >= outcome.startPassRate ? Theme.success : Theme.warning)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.m).background(Theme.chromeBg)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        if outcome.edits.isEmpty {
                            Text(model.t("eval.improve.noEdits")).font(.sfBodyM).foregroundStyle(.secondary)
                        } else {
                            Text(model.t("eval.improve.editsCount", outcome.edits.count))
                                .font(.sfFieldLabel).foregroundStyle(Theme.tertiaryOnMaterial)
                            ForEach(outcome.edits) { edit in editRow(edit) }
                        }
                    }
                    .padding(Space.l)
                }

                HStack {
                    Button(model.t("eval.improve.discard")) { showImprove = false }
                    Spacer()
                    Button(model.t("eval.improve.apply")) {
                        strategy = outcome.improvedTeam
                        run = outcome.finalRun
                        regression = nil
                        showImprove = false
                        model.flashSuccess(model.t("eval.improve.applied", outcome.edits.count))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(outcome.edits.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(Space.l)
            }
            .frame(minWidth: 560, idealWidth: 680, minHeight: 380, idealHeight: 520)
            .background(Theme.appBg)
        }
    }

    private func editRow(_ edit: TeamEdit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.xs) {
                Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Theme.accent)
                Text(edit.roleName).font(.sfCaption2.weight(.semibold))
                Text(edit.field.rawValue).font(.sfFieldLabel).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.hairline.opacity(0.6)))
            }
            Text(edit.rationale).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(edit.after).font(.sfCode).foregroundStyle(Theme.ink)
                .lineLimit(4).truncationMode(.tail)
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
