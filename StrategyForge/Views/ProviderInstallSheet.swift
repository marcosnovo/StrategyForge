//
//  ProviderInstallSheet.swift
//  StrategyForge
//
//  Reusable one-tap install/connect sheet for a provider's CLI. Runs the npm
//  install with live progress and offers sign-in — used both from Settings and
//  proactively from the chat when a required engine is missing.
//

import SwiftUI

struct ProviderInstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    /// Called after a successful install so the caller can re-detect.
    var onConnected: () -> Void = {}

    enum State: Equatable { case running, needsNode, failed(String), done }
    @SwiftUI.State private var state: State = .running
    @SwiftUI.State private var log: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: provider.icon).foregroundStyle(provider.tint)
                Text(model.t("provider.installing", provider.displayName)).font(.sfCardTitle)
                Spacer()
                if state == .running { ProgressView().controlSize(.small) }
            }

            switch state {
            case .needsNode:
                Label(model.t("provider.needsNode"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                Link(model.t("provider.getNode"), destination: URL(string: "https://nodejs.org/en/download")!)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill")
                    .font(.callout).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
            case .done:
                Label(model.t("provider.installed"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(Theme.success)
            case .running:
                Text(model.t("provider.installNote")).font(.caption).foregroundStyle(.secondary)
            }

            ScrollView {
                Text(log.suffix(200).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 150)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.insetBg))

            HStack {
                Spacer()
                if state == .done {
                    Button(model.t("provider.signin")) { ProviderInstaller.launchSignIn(provider) }
                        .buttonStyle(.borderedProminent)
                }
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(state == .running)
            }
        }
        .padding(Space.l)
        .frame(width: 460)
        .task { await run() }
    }

    private func run() async {
        for await event in ProviderInstaller.install(provider) {
            switch event {
            case .log(let line): log.append(line)
            case .needsNode: state = .needsNode
            case .failed(let msg): state = .failed(msg)
            case .finished: state = .done; onConnected()
            }
        }
    }
}
