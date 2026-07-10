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
    }

    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: provider.icon)
                    .foregroundStyle(provider.tint)
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
    }
}
