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
            .background(.bar)
            .zoomWindowOnDoubleClick()
            Divider()

            // ScrollView + LazyVStack (not List(selection:)) so the macOS system
            // selection block never paints over our soft .selectedRow treatment.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    groupHeader(model.t("services.group.ai"))
                    ForEach(AIProvider.allCases) { p in row(p) }
                    groupHeader(model.t("services.group.tools")).padding(.top, Space.s)
                    ForEach(AppModel.DevTool.allCases) { t in toolRow(t) }
                }
                .padding(.horizontal, Space.s).padding(.top, Space.xs)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Frosted glass column: a translucent material shows the faint aurora as clean
        // neutral vibrancy; the (.bar) title header above keeps the glass accent too.
        .translucentColumn()
        .task { await model.refreshConnectedProviders() }
    }

    private func row(_ p: AIProvider) -> some View {
        let selected = model.selectedService == p && model.selectedTool == nil
        return CoralRow(title: p.displayName, selected: selected,
                        leading: { ProviderLogo(provider: p, size: 20, templateTint: p.tint) },
                        trailing: { statusText(p) })
            .onTapGesture { model.selectedService = p; model.selectedTool = nil }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
            .padding(.horizontal, Space.xs).padding(.bottom, 2)
    }

    /// A developer-tool row (GitHub / Git) — status is resolved live.
    private func toolRow(_ t: AppModel.DevTool) -> some View {
        let selected = model.selectedTool == t
        return CoralRow(title: t.displayName, selected: selected,
                        leading: {
                            Group {
                                if t == .github { GitHubMark(size: 17) }
                                else { Image(systemName: "arrow.triangle.branch").font(.system(size: 15)) }
                            }
                            .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                        },
                        trailing: { toolStatus(t) })
            .onTapGesture { model.selectedTool = t }
    }

    @ViewBuilder
    private func toolStatus(_ t: AppModel.DevTool) -> some View {
        let ok = t == .github ? GitHubCLI.isInstalled : CodeGit.isAvailable
        Label(model.t(ok ? "provider.connected" : "provider.notFound"),
              systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
            .font(.sfCaption2).foregroundStyle(ok ? Theme.success : .secondary)
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
    @State private var diag: DiagState = .idle
    @State private var showDetails = false
    /// Draft for the OpenAI API-key field (loaded from the Keychain on appear).
    @State private var apiKeyDraft = ""

    private enum DiagState: Equatable {
        case idle, running
        case healthy(String)                    // the live greeting reply
        case issue(ProviderDiagnostics.Finding) // a classified failure + its fix
    }

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
                if connected { diagnoseCard }
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
        .card()
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
        .card()
    }

    private var binaryCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("settings.binary")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            TextField(provider.binaryName, text: binaryBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.save(); Task { await model.refreshConnectedProviders() } }
        }
        .card()
    }

    /// Diagnose & fix: runs the full end-to-end check (resolve the CLI → one real
    /// one-shot), classifies any failure into a concrete cause, and offers a one-click
    /// remedy — so a user never has to read a log or open a Terminal to recover.
    private var diagnoseCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("provider.diagnose")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                Button {
                    runDiagnose()
                } label: {
                    if diag == .running { WorkingLogo(size: 16) }
                    else { Text(model.t("provider.diagnose.run")) }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(diag == .running)
            }
            switch diag {
            case .healthy(let snippet):
                Label(snippet.isEmpty ? model.t("provider.diagnose.healthy") : snippet,
                      systemImage: "checkmark.circle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            case .issue(let finding):
                issueView(finding)
            case .running:
                Text(model.t("provider.diagnose.running")).font(.sfCaption2).foregroundStyle(.secondary)
            case .idle:
                Text(model.t("provider.diagnose.hint")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    /// A classified failure: title + plain explanation + a one-click fix (and the raw
    /// CLI output tucked behind a "Details" disclosure).
    @ViewBuilder
    private func issueView(_ finding: ProviderDiagnostics.Finding) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(model.t("provider.issue.\(finding.issue.rawValue).title"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.sfBodyM.weight(.semibold)).foregroundStyle(Theme.danger)
            Text(model.t("provider.issue.\(finding.issue.rawValue).detail", provider.displayName))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                fixButton(finding.fix)
                Button(model.t("provider.diagnose.retest")) { runDiagnose() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if !finding.raw.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    Text(finding.raw)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.insetBg))
                } label: {
                    Text(model.t("provider.diagnose.details")).font(.sfCaption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// The primary remedy button for a finding, wired to the existing recovery flows.
    @ViewBuilder
    private func fixButton(_ fix: ProviderDiagnostics.Fix) -> some View {
        switch fix {
        case .connect:
            Button(model.t("provider.fix.connect")) { connecting = true }
                .buttonStyle(.moon).controlSize(.small)
        case .useAPIKey:
            Button(model.t("provider.fix.useKey")) {
                model.settings.openaiUseAPIKey = true; model.save()
                model.flashSuccess(model.t("provider.fix.useKey.done"))
            }
            .buttonStyle(.bordered).controlSize(.small)
        case .exportLog:
            Button(model.t("provider.fix.exportLog")) { model.exportDiagnostics() }
                .buttonStyle(.bordered).controlSize(.small)
        case .none:
            EmptyView()
        }
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
        .card()
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
        .card()
    }

    private func runDiagnose() {
        diag = .running
        showDetails = false
        let binary = model.settings.binary(for: provider)
        let modelID = provider.models.first?.id ?? ""
        let keys = model.providerAPIKeys()
        let effort = model.settings.codexReasoningEffort
        Task {
            let (finding, greeting) = await ProviderDiagnostics.check(
                provider: provider, binary: binary, modelID: modelID,
                apiKeys: keys, reasoningEffort: effort)
            if let finding {
                diag = .issue(finding)
            } else {
                diag = .healthy(String(greeting.prefix(140)))
            }
            await model.refreshConnectedProviders()
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

/// Status + connect guidance for a developer TOOL (GitHub CLI / Git). These use the
/// user's own CLI login (bring-your-own-auth), so we can't sign in for them — we
/// surface status and the exact commands, mirroring the AI-provider panels.
struct ToolConfigView: View {
    @Environment(AppModel.self) private var model
    let tool: AppModel.DevTool
    @State private var authed: Bool? = nil
    @State private var repoCount: Int? = nil

    private var installed: Bool { tool == .github ? GitHubCLI.isInstalled : CodeGit.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                statusCard
                connectCard
            }
            .padding(Space.xl).frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: tool) { await refresh() }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Group {
                if tool == .github { GitHubMark(size: 34) }
                else { Image(systemName: "arrow.triangle.branch").font(.system(size: 30)) }
            }
            .foregroundStyle(.primary).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName).font(.sfDisplay)
                Text(model.t("tool.\(tool.rawValue).sub")).font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            toolStatusRow(model.t("tool.installed"), ok: installed)
            if tool == .github, installed {
                toolStatusRow(model.t("tool.authenticated"), ok: authed ?? false, pending: authed == nil)
                if let n = repoCount {
                    Text(model.t("tool.github.repos", n)).font(.sfCaption2).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func toolStatusRow(_ label: String, ok: Bool, pending: Bool = false) -> some View {
        HStack {
            Text(label).font(.sfCallout)
            Spacer()
            if pending { WorkingLogo(size: 14) }
            else {
                Label(model.t(ok ? "provider.connected" : "provider.notFound"),
                      systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.sfCaption2.weight(.medium)).foregroundStyle(ok ? Theme.success : .secondary)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("tool.connect.title")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            Text(model.t("tool.\(tool.rawValue).connect")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack(spacing: Space.s) {
                Button(model.t("tool.recheck")) { Task { await refresh() } }.controlSize(.small)
                if let url = URL(string: tool == .github ? "https://cli.github.com" : "https://git-scm.com/downloads") {
                    Link(model.t("tool.docs"), destination: url).controlSize(.small)
                }
            }
        }
        .card()
    }

    private func refresh() async {
        guard tool == .github, GitHubCLI.isInstalled else { authed = installed ? true : false; return }
        authed = nil; repoCount = nil
        let ok = await GitHubCLI.isAuthenticated()
        authed = ok
        if ok { repoCount = await GitHubCLI.listRepos(limit: 100).count }
    }
}
