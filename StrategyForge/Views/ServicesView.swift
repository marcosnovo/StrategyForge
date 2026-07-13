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
            .zoomWindowOnDoubleClick()
            Divider()

            // ScrollView + LazyVStack (not List(selection:)) so the macOS system
            // selection block never paints over our soft .selectedRow treatment.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(AIProvider.allCases) { p in row(p) }
                }
                .padding(.horizontal, Space.s).padding(.top, Space.xs)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.appBg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .task { await model.refreshConnectedProviders() }
    }

    private func row(_ p: AIProvider) -> some View {
        let selected = model.selectedService == p
        return HStack(spacing: Space.s) {
            ProviderLogo(provider: p, size: 18, templateTint: p.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.displayName).font(.sfBodyM.weight(selected ? .semibold : .medium)).lineLimit(1)
                statusText(p)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, Space.xs)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedService = p }
        .selectedRow(selected, cornerRadius: 8)
        .hoverTint(cornerRadius: 8)
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
    /// Draft for the OpenAI API-key field (loaded from the Keychain on appear).
    @State private var apiKeyDraft = ""

    private enum TestState: Equatable { case idle, running, ok(String), fail(String) }

    private var connected: Bool { model.isConnected(provider) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                statusCard
                planCard
                if provider == .openai { codexModelCard }
                if provider.supportsReasoningEffort { reasoningEffortCard }
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
            ProviderConnectSheet(provider: provider) { Task { await model.refreshConnectedProviders() } }
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
                // Already connected — offer a discreet re-auth (web sign-in).
                Button(model.t("provider.reconnect")) { connecting = true }
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

    /// Your subscription plan (declared manually — no CLI exposes it), surfaced here
    /// and in Usage so the plan is obvious at a glance.
    private var planCard: some View {
        let current = model.providerPlan(provider)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("provider.plan")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                Picker("", selection: Binding(
                    get: { current ?? "" },
                    set: { model.setProviderPlan($0.isEmpty ? nil : $0, for: provider) })) {
                    Text(model.t("provider.plan.none")).tag("")
                    ForEach(provider.planOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Text(model.t("provider.plan.hint")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    if test == .running { WorkingLogo(size: 16) }
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

    /// OpenAI/Codex model control: honest note about the subscription constraint, plus
    /// an optional API key that re-enables explicit model selection.
    private var codexModelCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("provider.codex.model")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            Text(model.t("provider.codex.model.note")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(model.t("provider.codex.useKey"), isOn: Binding(
                get: { model.settings.openaiUseAPIKey },
                set: { model.settings.openaiUseAPIKey = $0; model.save() }))
                .toggleStyle(.switch)
            if model.settings.openaiUseAPIKey {
                HStack(spacing: Space.s) {
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder).font(.sfCode)
                    Button(model.t("common.save")) {
                        model.setOpenAIAPIKey(apiKeyDraft)
                        model.flashSuccess(model.t("provider.codex.keySaved"))
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasOpenAIAPIKey {
                        Button(role: .destructive) { model.setOpenAIAPIKey(nil); apiKeyDraft = "" } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Text(model.t(model.hasOpenAIAPIKey ? "provider.codex.keyPresent" : "provider.codex.keyHint"))
                    .font(.sfCaption2).foregroundStyle(model.hasOpenAIAPIKey ? Theme.success : .secondary)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
        .onAppear { if model.hasOpenAIAPIKey, apiKeyDraft.isEmpty { apiKeyDraft = model.openAIAPIKey ?? "" } }
    }

    /// Reasoning-effort picker (works with a ChatGPT-account login, unlike model choice).
    private var reasoningEffortCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("provider.codex.effort")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                Picker("", selection: Binding(
                    get: { model.settings.codexReasoningEffort },
                    set: { model.settings.codexReasoningEffort = $0; model.save() })) {
                    ForEach(AIProvider.reasoningEffortOptions, id: \.self) { opt in
                        Text(opt.isEmpty ? model.t("provider.codex.effort.default") : opt.capitalized).tag(opt)
                    }
                }
                .labelsHidden().fixedSize()
            }
            Text(model.t("provider.codex.effort.hint")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func runTest() {
        test = .running
        let runner = CLIOneShotRunner(binaries: [provider: model.settings.binary(for: provider)],
                                      apiKeys: model.providerAPIKeys(),
                                      reasoningEffort: model.settings.codexReasoningEffort)
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
