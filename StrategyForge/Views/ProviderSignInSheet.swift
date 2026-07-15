//
//  ProviderSignInSheet.swift
//  StrategyForge
//
//  Web sign-in for a provider's CLI without an ugly empty Terminal: it runs the
//  CLI's login as a background subprocess (which opens the browser + runs the OAuth
//  callback server), streams progress here, and surfaces the sign-in URL as a button.
//  On failure — e.g. a CLI whose login needs a real TTY — it offers a Terminal fallback.
//

import SwiftUI

struct ProviderSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    /// Called after a successful sign-in so the caller can re-detect.
    var onConnected: () -> Void = {}

    enum Phase: Equatable { case running, done, failed(String) }
    @State private var phase: Phase = .running
    @State private var log: [String] = []
    @State private var url: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                Text(model.t("provider.signin.title", provider.displayName)).font(.sfCardTitle)
                Spacer()
                if phase == .running { WorkingLogo(size: 16) }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: Theme.innerCorner, material: .regularMaterial)

            switch phase {
            case .running:
                Label(model.t("provider.signin.waiting"), systemImage: "safari")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url, let u = URL(string: url) {
                    Link(destination: u) {
                        Label(model.t("provider.signin.openPage"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.moon)
                }
            case .done:
                Label(model.t("provider.signin.done"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(Theme.success)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill")
                    .font(.caption).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                // Some CLIs' login needs a real terminal — offer that as a fallback.
                Button(model.t("provider.signin.terminal")) { ProviderInstaller.launchSignIn(provider) }
                    .buttonStyle(.reefOutline)
            }

            ScrollView {
                Text(log.suffix(200).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 130)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg))

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

    private func run() async {
        for await event in ProviderInstaller.signIn(provider) {
            switch event {
            case .log(let line):
                log.append(line)
                if url == nil, let u = ProviderInstaller.firstURL(in: line) { url = u.absoluteString }
            case .finished:
                phase = .done
                onConnected()
            case .failed(let msg):
                phase = .failed(msg)
            case .needsNode:
                phase = .failed(model.t("provider.needsNode"))
            case .needsCode:
                break   // this legacy sheet doesn't collect the code; ProviderConnectSheet does
            }
        }
    }
}
