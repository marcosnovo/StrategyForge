//
//  ServicesView.swift
//  StrategyForge
//
//  The "Services" section reached from the nav rail: the second column lists the
//  AI providers with their live status, and selecting one shows its connect/config
//  in the main area (instead of hiding it away in Settings).
//

import SwiftUI

/// Second column: the list of AI services with connection status.
struct ServicesListColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Text(model.t("settings.connected")).font(.sfCardTitle)
                Spacer()
            }
            .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.s)
            .background(Theme.appBg)
            Divider()

            List(selection: $model.selectedService) {
                ForEach(AIProvider.allCases) { p in
                    row(p).tag(p)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.appBg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .task { await model.refreshConnectedProviders() }
    }

    private func row(_ p: AIProvider) -> some View {
        HStack(spacing: Space.s) {
            ProviderLogo(provider: p, size: 18, templateTint: p.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.displayName).font(.sfBodyM.weight(.medium)).lineLimit(1)
                statusText(p)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusText(_ p: AIProvider) -> some View {
        if model.isConnected(p) {
            Label(model.t("provider.connected"), systemImage: "checkmark.circle.fill")
                .font(.sfCaption2).foregroundStyle(Theme.success)
        } else {
            Label(model.t("provider.notFound"), systemImage: "xmark.circle")
                .font(.sfCaption2).foregroundStyle(.secondary)
        }
    }
}

/// Main area: connect/configure the selected provider.
struct ProviderConfigView: View {
    @Environment(AppModel.self) private var model
    let provider: AIProvider
    @State private var connecting = false
    @State private var test: TestState = .idle

    private enum TestState: Equatable { case idle, running, ok(String), fail(String) }

    private var connected: Bool { model.isConnected(provider) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                statusCard
                binaryCard
                if connected { testCard }
                if !provider.isExecutable { soonNote }
            }
            .padding(Space.xl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: provider) { await model.refreshConnectedProviders() }
        .sheet(isPresented: $connecting) {
            ProviderInstallSheet(provider: provider) { Task { await model.refreshConnectedProviders() } }
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            ProviderLogo(provider: provider, size: 40, templateTint: provider.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.sfDisplay)
                Text(model.t(provider.connectHelpKey)).font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: Space.m) {
            if connected {
                Label(model.t("provider.connected"), systemImage: "checkmark.circle.fill")
                    .font(.sfCardTitle).foregroundStyle(Theme.success)
                Spacer()
                // Already connected — offer a discreet re-auth, not a prompt.
                Button(model.t("provider.reconnect")) { ProviderInstaller.launchSignIn(provider) }
                    .buttonStyle(.plain).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                Label(model.t("provider.notFound"), systemImage: "xmark.circle")
                    .font(.sfCardTitle).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("provider.connect")) { connecting = true }
                    .buttonStyle(.moon)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var binaryCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("settings.binary")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            TextField(provider.binaryName, text: binaryBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.save(); Task { await model.refreshConnectedProviders() } }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Runs one real one-shot through the provider's CLI so you can verify it
    /// end-to-end (works today for Claude; validates Codex/Gemini once installed).
    private var testCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("provider.test")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                Button {
                    runTest()
                } label: {
                    if test == .running { DotSpinner(size: 16) }
                    else { Text(model.t("provider.test.run")) }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(test == .running)
            }
            switch test {
            case .ok(let snippet):
                Label(snippet.isEmpty ? model.t("provider.test.ok") : snippet, systemImage: "checkmark.circle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            case .fail(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                Text(model.t("provider.test.hint")).font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func runTest() {
        test = .running
        let runner = CLIOneShotRunner(binaries: [provider: model.settings.binary(for: provider)])
        let modelID = provider.models.first?.id ?? ""
        Task {
            do {
                let r = try await runner.run(prompt: "Reply with a short one-line greeting.",
                                             provider: provider, model: modelID, cwd: nil)
                test = .ok(String(r.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)))
            } catch {
                test = .fail((error as? OneShotError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private var soonNote: some View {
        Label(model.t("provider.soon.note"), systemImage: "clock")
            .font(.sfCallout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var binaryBinding: Binding<String> {
        switch provider {
        case .claude: return Binding(get: { model.settings.claudeBinary }, set: { model.settings.claudeBinary = $0 })
        case .openai: return Binding(get: { model.settings.codexBinary }, set: { model.settings.codexBinary = $0 })
        case .gemini: return Binding(get: { model.settings.geminiBinary }, set: { model.settings.geminiBinary = $0 })
        }
    }
}
