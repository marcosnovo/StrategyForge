//
//  ConnectedServicesView.swift
//  StrategyForge
//
//  The "Connected services" settings section: each AI provider (Claude, ChatGPT·
//  Codex, Gemini) shown with live detection of its CLI, a binary-path override, and
//  how to connect it with the user's own subscription login. Claude runs today; the
//  others are connectable now and become runnable as their engines land.
//

import SwiftUI

struct ConnectedServicesSection: View {
    @Environment(AppModel.self) private var model

    enum DetectStatus: Equatable { case checking, found(String), missing }
    @State private var status: [AIProvider: DetectStatus] = [:]

    // One-tap install/connect flow.
    @State private var connecting: AIProvider?
    @State private var installLog: [String] = []
    @State private var installState: InstallUIState = .running
    enum InstallUIState: Equatable { case running, needsNode, failed(String), done }

    var body: some View {
        Section(model.t("settings.connected")) {
            Text(model.t("settings.connected.caption"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(AIProvider.allCases) { provider in
                providerRow(provider)
            }
        }
        .task { await detectAll() }
        .sheet(item: $connecting) { provider in connectSheet(provider) }
    }

    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                    .frame(width: 20)
                Text(provider.displayName).font(.body.weight(.medium))
                if !provider.isExecutable {
                    Text(model.t("provider.soon"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.hairline))
                }
                Spacer()
                statusBadge(provider)
                actionButton(provider)
            }

            HStack {
                Text(model.t("settings.binary")).font(.caption).foregroundStyle(.secondary)
                TextField(provider.binaryName, text: binaryBinding(provider))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.save(); Task { await detect(provider) } }
            }

            Text(model.t(provider.connectHelpKey))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ provider: AIProvider) -> some View {
        switch status[provider] ?? .checking {
        case .checking:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text(model.t("provider.checking")).font(.caption) }
                .foregroundStyle(.secondary)
        case .found:
            Label(model.t("provider.connected"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(Theme.success)
        case .missing:
            Label(model.t("provider.notFound"), systemImage: "xmark.circle")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// Primary action per provider: install+connect when missing, or re-sign-in.
    @ViewBuilder
    private func actionButton(_ provider: AIProvider) -> some View {
        switch status[provider] ?? .checking {
        case .missing:
            Button(model.t("provider.connect")) { startConnect(provider) }
                .controlSize(.small).buttonStyle(.moon)
        case .found:
            Button(model.t("provider.reconnect")) { ProviderInstaller.launchSignIn(provider) }
                .controlSize(.small).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        case .checking:
            EmptyView()
        }
    }

    // MARK: Install / connect flow

    private func startConnect(_ provider: AIProvider) {
        installLog = []
        installState = .running
        connecting = provider
        Task {
            for await event in ProviderInstaller.install(provider) {
                switch event {
                case .log(let line): installLog.append(line)
                case .needsNode: installState = .needsNode
                case .failed(let msg): installState = .failed(msg)
                case .finished:
                    installState = .done
                    await detect(provider)
                }
            }
        }
    }

    @ViewBuilder
    private func connectSheet(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                Text(model.t("provider.installing", provider.displayName)).font(.sfCardTitle)
                Spacer()
                if installState == .running { ProgressView().controlSize(.small) }
            }

            switch installState {
            case .needsNode:
                Label(model.t("provider.needsNode"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Link(model.t("provider.getNode"), destination: URL(string: "https://nodejs.org/en/download")!)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill")
                    .font(.callout).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            case .done:
                Label(model.t("provider.installed"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(Theme.success)
            case .running:
                Text(model.t("provider.installNote")).font(.caption).foregroundStyle(.secondary)
            }

            // Live installer output.
            ScrollView {
                Text(installLog.suffix(200).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 160)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.insetBg))

            HStack {
                Spacer()
                if installState == .done {
                    Button(model.t("provider.signin")) { ProviderInstaller.launchSignIn(provider) }
                        .buttonStyle(.moon)
                }
                Button(model.t("common.done")) { connecting = nil }
                    .keyboardShortcut(.defaultAction)
                    .disabled(installState == .running)
            }
        }
        .padding(Space.l)
        .frame(width: 460)
    }

    private func binaryBinding(_ provider: AIProvider) -> Binding<String> {
        switch provider {
        case .claude: return Binding(get: { model.settings.claudeBinary }, set: { model.settings.claudeBinary = $0 })
        case .openai: return Binding(get: { model.settings.codexBinary }, set: { model.settings.codexBinary = $0 })
        case .gemini: return Binding(get: { model.settings.geminiBinary }, set: { model.settings.geminiBinary = $0 })
        }
    }

    private func detectAll() async {
        for provider in AIProvider.allCases { await detect(provider) }
    }

    private func detect(_ provider: AIProvider) async {
        status[provider] = .checking
        let name = model.settings.binary(for: provider)
        // resolveBinary spawns a login shell — keep it off the main actor.
        let path = await Task.detached { ClaudeRunner.resolveBinary(name) }.value
        status[provider] = path.map { .found($0) } ?? .missing
        // Keep the app-wide connected set in sync so pickers unlock immediately.
        if path != nil { model.connectedProviders.insert(provider) }
        else { model.connectedProviders.remove(provider) }
    }
}
