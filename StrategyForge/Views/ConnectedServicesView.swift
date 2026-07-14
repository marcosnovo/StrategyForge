//
//  ConnectedServicesView.swift
//  StrategyForge
//
//  The "Connected services" settings section: each AI provider (Claude, ChatGPT·
//  Codex, Gemini) with live CLI detection, a binary-path override, a one-tap
//  connect/reconnect that runs entirely in-app (hidden PTY, no Terminal), and a
//  connection test that does a real end-to-end round-trip.
//

import SwiftUI

struct ConnectedServicesSection: View {
    @Environment(AppModel.self) private var model

    enum DetectStatus: Equatable { case checking, found(String), missing }
    @State private var status: [AIProvider: DetectStatus] = [:]
    /// Presents the in-app connect/reconnect flow (install → hidden-PTY sign-in).
    @State private var connecting: AIProvider?
    /// Per-provider connection-test result.
    enum TestState: Equatable { case idle, running, ok(String), fail(String) }
    @State private var test: [AIProvider: TestState] = [:]

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
        .sheet(item: $connecting) { provider in
            ProviderConnectSheet(provider: provider) {
                Task { await detect(provider); await model.refreshUsage() }
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                    .frame(width: 20)
                Text(provider.displayName).font(.body.weight(.medium))
                Spacer()
                statusBadge(provider)
                actionButtons(provider)
            }

            // The connection-test result (a real round-trip) when present.
            switch test[provider] ?? .idle {
            case .running:
                Label(model.t("provider.diagnose.running"), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            case .ok(let s):
                Label(s.isEmpty ? model.t("provider.diagnose.healthy") : s, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.success).lineLimit(2)
            case .fail(let s):
                // A failed test is almost always a sign-in problem — offer to review /
                // reconnect the session right here (in-app, no Terminal) instead of just
                // telling the user to do it.
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Label(s, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.danger).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(model.t("provider.test.reviewSession")) { connecting = provider }
                        .controlSize(.small).buttonStyle(.moon)
                }
            case .idle:
                EmptyView()
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
            HStack(spacing: 4) { WorkingLogo(size: 16); Text(model.t("provider.checking")).font(.caption) }
                .foregroundStyle(.secondary)
        case .found:
            Label(model.t("provider.connected"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(Theme.success)
        case .missing:
            Label(model.t("provider.notFound"), systemImage: "xmark.circle")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// Test + connect/reconnect — all in-app (no Terminal).
    @ViewBuilder
    private func actionButtons(_ provider: AIProvider) -> some View {
        switch status[provider] ?? .checking {
        case .missing:
            Button(model.t("provider.connect")) { connecting = provider }
                .controlSize(.small).buttonStyle(.moon)
        case .found:
            Button(model.t("provider.test.run")) { runTest(provider) }
                .controlSize(.small).disabled(test[provider] == .running)
            Button(model.t("provider.reconnect")) { connecting = provider }
                .controlSize(.small).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        case .checking:
            EmptyView()
        }
    }

    /// The bounded result of a connection test — carries only Sendable payload so it can
    /// cross the task-group boundary. `.timedOut` means the CLI never replied in time
    /// (Gemini's TUI one-shot can hang), which we surface instead of spinning forever.
    private enum TestOutcome: Sendable {
        case completed(issueRaw: String?, greeting: String)
        case timedOut
    }

    /// A real end-to-end check (resolve the CLI + one one-shot), classified — but bounded
    /// by a timeout so a hung CLI can't leave the test spinning. Cancelling the check
    /// terminates its subprocess.
    private func runTest(_ provider: AIProvider) {
        test[provider] = .running
        let binary = model.settings.binary(for: provider)
        let modelID = provider.models.first?.id ?? ""
        let keys = model.providerAPIKeys()
        let effort = model.settings.codexReasoningEffort
        Task {
            let outcome = await withTaskGroup(of: TestOutcome.self) { group -> TestOutcome in
                group.addTask {
                    let (finding, greeting) = await ProviderDiagnostics.check(
                        provider: provider, binary: binary, modelID: modelID,
                        apiKeys: keys, reasoningEffort: effort)
                    return .completed(issueRaw: finding?.issue.rawValue, greeting: greeting)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(45))
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                group.cancelAll()   // cancellation terminates the CLI subprocess
                return first
            }
            switch outcome {
            case .completed(let issueRaw, let greeting):
                if let issueRaw {
                    test[provider] = .fail(model.t("provider.issue.\(issueRaw).title"))
                } else {
                    test[provider] = .ok(String(greeting.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)))
                }
            case .timedOut:
                test[provider] = .fail(model.t("provider.test.timeout"))
            }
            await detect(provider)
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
        // Keep the app-wide connected set in sync so pickers unlock immediately.
        if path != nil { model.connectedProviders.insert(provider) }
        else { model.connectedProviders.remove(provider) }
    }
}
