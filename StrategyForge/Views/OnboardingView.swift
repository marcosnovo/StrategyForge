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
    /// The primary path: describe a task and let AI build the team (onboarding gate).
    var onDescribeTask: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.m) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                    .breathingGlow(color: Theme.coral)
                Text(model.t("onboard.title")).font(.sfDisplay)
            }
            .staggeredAppear(index: 0)

            Text(model.t("onboard.intro"))
                .font(.sfBodyM)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppear(index: 1)

            // Show — not just tell — what "a team of agents" means: a live,
            // animated topology of a real sample strategy.
            VStack(alignment: .leading, spacing: Space.xs) {
                StrategyDiagramView(strategy: StrategyLibrary.orchestratorWorkers())
                    .frame(height: 188)
                    .padding(Space.s)
                    // Soft rounded glass frame — the topology floats over the aurora.
                    .glassPanel(cornerRadius: Theme.corner)
                Text(model.t("onboard.diagramCaption"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            .staggeredAppear(index: 2)

            VStack(alignment: .leading, spacing: Space.l) {
                step(1, "onboard.step1.title", "onboard.step1.desc")
                step(2, "onboard.step2.title", "onboard.step2.desc")
                step(3, "onboard.step3.title", "onboard.step3.desc")
            }
            .staggeredAppear(index: 3)

            Label(model.t("onboard.note"), systemImage: "info.circle.fill")
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.accentSoft))
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppear(index: 4)

            // Readiness before value: surface what the app needs to actually run
            // (a connected CLI) up front, not after the user has built a team — the
            // #1 activation gate for a tool that drives external CLIs.
            readinessStrip.staggeredAppear(index: 5)

            HStack {
                Button(model.t("onboard.skip")) {
                    Analytics.log(.onboardingPathSelected(path: "skip"))
                    Analytics.log(.onboardingSkipped)
                    dismiss()
                }
                Spacer()
                Button(model.t("onboard.browse")) {
                    Analytics.log(.onboardingPathSelected(path: "browse"))
                    Analytics.log(.onboardingCompleted)
                    dismiss()
                    onCreate()
                }
                Button {
                    Analytics.log(.onboardingPathSelected(path: "describe"))
                    Analytics.log(.onboardingCompleted)
                    dismiss()
                    onDescribeTask()
                } label: {
                    Label(model.t("onboard.describeTask"), systemImage: "sparkles")
                }
                .buttonStyle(.moon)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .staggeredAppear(index: 5)
        }
        .padding(Space.xl + Space.s)
        .frame(width: 560)
        // Static ambient wash — always mounted (never inserted/removed with an
        // animation; see the TimelineView-over-material note in ChatView).
        .background(AuroraBackground(intensity: 0.9))
        .task { Analytics.log(.onboardingStarted) }
    }

    /// Environment-readiness spine: a Gatekeeper pre-empt + a per-provider status
    /// row, so the user knows what's needed to run before they invest in a team.
    private var readinessStrip: some View {
        let ready = model.connectedProviders.contains(.claude)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: ready ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                    .foregroundStyle(ready ? Theme.success : Theme.warning)
                Text(model.t(ready ? "onboard.ready.title" : "onboard.ready.setup"))
                    .font(.sfCardTitle)
                Spacer()
                Button(model.t("onboard.ready.connect")) {
                    dismiss()
                    model.navSection = .services
                }
                .font(.sfCaption2)
            }
            // Per-provider status (Claude is the default engine; the others are
            // optional and unlock cross-provider teams).
            HStack(spacing: Space.m) {
                ForEach(AIProvider.allCases) { p in
                    let on = model.isConnected(p)
                    HStack(spacing: 5) {
                        Image(systemName: on ? "circle.fill" : "circle")
                            .scaledFont(8)
                            .foregroundStyle(on ? Theme.success : Theme.secondaryOnMaterial)
                        Text(p.displayName).font(.sfCaption2)
                            .foregroundStyle(on ? .primary : .secondary)
                    }
                }
            }
            Label(model.t("onboard.gatekeeper"), systemImage: "lock.shield")
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent glass so the readiness strip floats over the aurora wash.
        .glassPanel(cornerRadius: Theme.innerCorner)
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
