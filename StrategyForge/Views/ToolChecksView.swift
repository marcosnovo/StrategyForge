//
//  ToolChecksView.swift
//  StrategyForge
//
//  Tool unit tests card (article #5): deterministic checks that run a command and assert
//  on its output — no model in the loop, so they're fast and repeatable. Catches "tool
//  bugs wearing a costume" before the team is trusted.
//

import SwiftUI

struct ToolChecksView: View {
    @Environment(AppModel.self) private var model
    @Binding var strategy: Strategy

    @State private var results: [ToolCheckResult] = []
    @State private var isBusy = false
    @State private var progress: (done: Int, total: Int)?

    private var checks: [ToolCheck] { strategy.toolChecks }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("wrench.and.screwdriver", model.t("toolcheck.title"), subtitle: model.t("toolcheck.subtitle"))

            if checks.isEmpty {
                Text(model.t("toolcheck.empty")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                summaryRow
                ForEach(Array(checks.enumerated()), id: \.element.id) { i, _ in checkRow(i) }
            }

            actions
            if let p = progress, isBusy {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                Text(model.t("eval.progress", p.done, p.total)).font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var summaryRow: some View {
        let ran = results.filter { r in checks.contains { $0.id == r.checkID } }
        let passed = ran.filter(\.passed).count
        return HStack(spacing: Space.s) {
            Text(model.t("toolcheck.count", checks.count)).font(.sfCaption2).foregroundStyle(.secondary)
            Spacer()
            if !ran.isEmpty {
                let ok = passed == ran.count
                Label(model.t(ok ? "toolcheck.allPass" : "toolcheck.someFail"),
                      systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.sfCaption2.weight(.semibold))
                    .foregroundStyle(ok ? Theme.success : Theme.danger)
                Text("\(passed)/\(ran.count)").font(.sfMono).foregroundStyle(.primary)
            }
        }
    }

    private func checkRow(_ i: Int) -> some View {
        let check = checks[i]
        let result = results.first { $0.checkID == check.id }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.s) {
                // Verdict marker (pass = green circle, fail = red square, unrun = hollow).
                Group {
                    if let r = result {
                        if r.passed { Circle().fill(Theme.success) }
                        else { RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.danger) }
                    } else { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                }
                .frame(width: 9, height: 9)
                TextField(model.t("toolcheck.name"), text: bind(i).name)
                    .textFieldStyle(.plain).font(.sfCaption2.weight(.medium))
                Spacer(minLength: 0)
                Button { strategy.toolChecks.remove(at: i) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
            TextField(model.t("toolcheck.command"), text: bind(i).command, axis: .vertical)
                .textFieldStyle(.plain).font(.sfCode).lineLimit(1...3)
                .padding(.horizontal, Space.s).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.insetBg))
            HStack(spacing: Space.s) {
                TextField(model.t("toolcheck.expectContains"), text: bind(i).expectContains)
                    .textFieldStyle(.plain).font(.sfCaption2)
                Toggle(model.t("toolcheck.exitZero"), isOn: bind(i).expectExitZero)
                    .toggleStyle(.checkbox).font(.sfCaption2).fixedSize()
            }
            if let r = result, !r.passed {
                Text(r.reason).font(.sfCaption2).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        HStack(spacing: Space.s) {
            Button {
                strategy.toolChecks.append(ToolCheck())
            } label: { Label(model.t("toolcheck.add"), systemImage: "plus") }
                .buttonStyle(.bordered).disabled(isBusy)
            if !checks.isEmpty {
                Button { Task { await runChecks() } } label: {
                    Label(model.t("toolcheck.run"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).disabled(isBusy)
            }
        }
    }

    /// A stable binding into the strategy's toolChecks by index.
    private func bind(_ i: Int) -> Binding<ToolCheck> {
        Binding(get: { strategy.toolChecks[i] },
                set: { strategy.toolChecks[i] = $0 })
    }

    private func runChecks() async {
        isBusy = true; progress = (0, checks.count)
        defer { isBusy = false; progress = nil }
        let out = await ToolChecks.run(checks: checks, runner: ShellCommandRunner(), cwd: nil) { done, total in
            Task { @MainActor in progress = (done, total) }
        }
        results = out
        let passed = out.filter(\.passed).count
        model.flashSuccess(model.t("toolcheck.doneBanner", passed, out.count))
    }
}
