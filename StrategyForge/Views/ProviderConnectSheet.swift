//
//  ProviderConnectSheet.swift
//  StrategyForge
//
//  One simple, direct "Connect" flow for a provider — Coral does everything: it
//  installs the CLI silently if it's missing (to a user-writable prefix, no sudo),
//  then runs the web sign-in (opens the browser, no Terminal). A two-step indicator
//  makes the (few) steps clear; a Terminal fallback appears only if something fails.
//

import SwiftUI

struct ProviderConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    /// Called after a successful connect so the caller can re-detect.
    var onConnected: () -> Void = {}

    enum Phase: Equatable { case installing, signingIn, done, failed(String) }
    @State private var phase: Phase = .installing
    @State private var log: [String] = []
    @State private var url: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                Text(model.t("provider.connect.title", provider.displayName)).font(.sfCardTitle)
                Spacer()
                if phase == .installing || phase == .signingIn { DotSpinner(size: 16) }
            }

            steps

            statusLine

            if phase == .signingIn, let url, let u = URL(string: url) {
                Link(destination: u) {
                    Label(model.t("provider.signin.openPage"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.moon)
            }
            if case .failed = phase {
                Button(model.t("provider.signin.terminal")) { ProviderInstaller.launchSignIn(provider) }
                    .buttonStyle(.bordered)
            }

            ScrollView {
                Text(log.suffix(200).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 120)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.insetBg))

            HStack {
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
        .frame(width: 460)
        .task { await run() }
    }

    // MARK: Steps

    private var steps: some View {
        HStack(spacing: Space.s) {
            stepPill(1, model.t("provider.connect.step.install"),
                     state: phase == .installing ? .active : .done)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            stepPill(2, model.t("provider.connect.step.signin"),
                     state: phase == .signingIn ? .active : (phase == .done ? .done : .pending))
        }
    }

    private enum StepState { case pending, active, done }
    private func stepPill(_ n: Int, _ label: String, state: StepState) -> some View {
        let color: Color = state == .active ? Theme.accent : (state == .done ? Theme.success : Theme.secondaryOnMaterial)
        return HStack(spacing: 5) {
            if state == .done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
            } else {
                Text("\(n)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 15, height: 15).background(Circle().fill(color.opacity(0.18)))
            }
            Text(label).font(.sfCaption2.weight(.medium))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .installing:
            Label(model.t("provider.connect.installing"), systemImage: "arrow.down.circle")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .signingIn:
            Label(model.t("provider.signin.waiting"), systemImage: "safari")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .done:
            Label(model.t("provider.connect.done"), systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(Theme.success)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run() async {
        for await event in ProviderInstaller.connect(provider) {
            switch event {
            case .phase(let s): phase = (s == .installing ? .installing : .signingIn)
            case .log(let l): log.append(l)
            case .url(let u): url = u
            case .needsNode: phase = .failed(model.t("provider.needsNode"))
            case .failed(let m): phase = .failed(m)
            case .done: phase = .done; onConnected()
            }
        }
    }
}
