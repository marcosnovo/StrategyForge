//
//  OnboardingView.swift
//  StrategyForge
//
//  First-run welcome that explains, in plain language, what the app does and the
//  three steps — and, crucially, that it only writes files (it does not run agents).
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called when the user wants to jump straight into creating a configuration.
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.m) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                Text(model.t("onboard.title")).font(.sfDisplay)
            }

            Text(model.t("onboard.intro"))
                .font(.sfBodyM)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.l) {
                step(1, "onboard.step1.title", "onboard.step1.desc")
                step(2, "onboard.step2.title", "onboard.step2.desc")
                step(3, "onboard.step3.title", "onboard.step3.desc")
            }

            Label(model.t("onboard.note"), systemImage: "info.circle.fill")
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.accentSoft))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(model.t("onboard.skip")) { dismiss() }
                Spacer()
                Button(model.t("onboard.cta")) {
                    dismiss()
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl + Space.s)
        .frame(width: 560)
    }

    private func step(_ number: Int, _ titleKey: String, _ descKey: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            StepBadge(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t(titleKey)).font(.sfCardTitle)
                Text(model.t(descKey)).font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private func previewModel(_ lang: AppLanguage) -> AppModel {
    let m = AppModel(); m.settings.language = lang; return m
}

#Preview("EN") { OnboardingView(onCreate: {}).environment(previewModel(.en)) }
#Preview("ES") { OnboardingView(onCreate: {}).environment(previewModel(.es)) }
