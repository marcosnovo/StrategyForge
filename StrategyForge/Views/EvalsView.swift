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
    @State private var isBusy = false
    @State private var progress: (done: Int, total: Int)?
    @State private var phase: Phase = .idle
    private enum Phase { case idle, generating, running }

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
                if let run { verdictList(run) }
                ForEach(scenarios) { scenario in scenarioRow(scenario, run: run) }
            }

            actions
            if let p = progress, isBusy {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text(model.t("eval.progress", p.done, p.total)).font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .card()
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

    @ViewBuilder private func verdictList(_ run: EvalRun) -> some View {
        Text(model.t("eval.threshold", Int((suite.passThreshold * 100).rounded())))
            .font(.sfCaption2).foregroundStyle(.tertiary)
    }

    private func scenarioRow(_ scenario: EvalScenario, run: EvalRun?) -> some View {
        let result = run?.results.first { $0.scenarioID == scenario.id }
        return HStack(alignment: .top, spacing: Space.s) {
            // Verdict marker: pass = green circle, fail = red square (colorblind-safe),
            // unrun = hollow.
            Group {
                if let r = result {
                    if r.passed {
                        Circle().fill(Theme.success)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.danger)
                    }
                } else {
                    Circle().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .frame(width: 9, height: 9).padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(scenario.prompt).font(.sfCaption2).foregroundStyle(Theme.ink).lineLimit(2)
                Text(model.t(scenario.category.labelKey)).font(.sfFieldLabel).foregroundStyle(.tertiary)
                if let r = result, !r.passed {
                    Text(r.reason).font(.sfCaption2).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scenario.prompt)
        .accessibilityValue(result.map { $0.passed ? model.t("eval.pass") : "\(model.t("eval.fail")): \($0.reason)" } ?? "")
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
        }
    }

    // MARK: Drive the engine

    private func generate() async {
        isBusy = true; phase = .generating; defer { isBusy = false; phase = .idle }
        let scenarios = await EvalRunner.generate(team: strategy, count: 12,
                                                  runner: model.oneShotRunner(readOnly: false))
        guard !scenarios.isEmpty else { model.flashFailure(model.t("eval.generateFailed")); return }
        var s = strategy.evalSuite ?? EvalSuite()
        s.scenarios = scenarios
        strategy.evalSuite = s
        run = nil   // stale results no longer match the new scenarios
        model.flashSuccess(model.t("eval.generated", scenarios.count))
    }

    private func runEvals() async {
        isBusy = true; phase = .running; progress = (0, scenarios.count)
        defer { isBusy = false; phase = .idle; progress = nil }
        let outcome = await EvalRunner.run(
            team: strategy, suite: suite, cwd: nil,
            answerRunner: model.oneShotRunner(readOnly: false),
            judgeRunner: model.oneShotRunner(readOnly: true)) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
        run = outcome
        model.flashSuccess(model.t("eval.doneBanner", outcome.passed, outcome.total))
    }
}
