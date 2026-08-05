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
    @State private var requesting = false
    @State private var requestDraft = ""

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
                    if aiConnectedCount == 0 { firstRunNudge }
                    groupHeader(model.t("services.group.ai"),
                                count: "\(aiConnectedCount)/\(AIProvider.allCases.count)")
                    ForEach(AIProvider.allCases) { p in row(p) }
                    groupHeader(model.t("services.group.tools"),
                                count: "\(toolsConnectedCount)/\(AppModel.DevTool.allCases.count)")
                        .padding(.top, Space.s)
                    ForEach(AppModel.DevTool.allCases) { t in toolRow(t) }
                    comingSoonGroup
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
        .sheet(isPresented: $requesting) { requestSheet }
    }

    /// The roadmap: providers Coral doesn't run yet, which the user can upvote to tell us
    /// which to build next. No fake counts — a vote is saved locally (and, opt-in, logged).
    @ViewBuilder
    private var comingSoonGroup: some View {
        groupHeader(model.t("services.group.soon")).padding(.top, Space.s)
        ForEach(FutureProvider.all) { f in futureRow(f) }
        // "Request another" — a free-text path for anything not on the ballot.
        CoralRow(model.t("future.request"), systemImage: "plus.circle")
            .onTapGesture { requesting = true }
        // Honest framing: not live, votes local, only shared if telemetry is on.
        VStack(alignment: .leading, spacing: 2) {
            Text(model.t("future.footer")).font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if model.futureVoteCount > 0 {
                Text(model.t("future.voted.count", model.futureVoteCount))
                    .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Space.xs).padding(.top, Space.xs).padding(.bottom, Space.s)
    }

    /// A future-provider row: a quiet reef-tinted glyph, the name + one-line "why", and a
    /// vote pill. The row itself isn't selectable (no detail yet) — only the pill acts.
    private func futureRow(_ f: FutureProvider) -> some View {
        CoralRow(title: f.name, subtitle: model.t(f.taglineKey),
                 leading: {
                     Image(systemName: f.icon).font(.system(size: 15))
                         .foregroundStyle(f.tint.opacity(0.75))
                         .frame(width: 26, height: 26)
                         .background(Circle().fill(f.tint.opacity(0.12)))
                 },
                 trailing: { VotePill(voted: model.hasVotedFuture(f.id)) { model.toggleFutureVote(f.id) } })
    }

    /// The "Request another provider" composer — a small sheet, one field, straight to
    /// the team's list (persisted locally + logged when telemetry is on).
    private var requestSheet: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.t("future.request.title")).font(.sfCardTitle)
            Text(model.t("future.request.hint")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(model.t("future.request.placeholder"), text: $requestDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitRequest)
            HStack {
                Spacer()
                Button(model.t("common.cancel")) { requesting = false }
                Button(model.t("future.request.send"), action: submitRequest)
                    .buttonStyle(.moon)
                    .disabled(requestDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.l)
        .frame(width: 380)
    }

    private func submitRequest() {
        let text = requestDraft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        model.requestFutureProvider(text)
        requestDraft = ""
        requesting = false
        model.flashSuccess(model.t("future.request.done"))
    }

    /// How many AI providers / dev tools are live — surfaced in the group headers so the
    /// column reads as a dashboard, and driving the first-run nudge.
    private var aiConnectedCount: Int { AIProvider.allCases.filter { model.isConnected($0) }.count }
    private var toolsConnectedCount: Int {
        (GitHubCLI.isInstalled ? 1 : 0) + (CodeGit.isAvailable ? 1 : 0)
    }

    /// A quiet coral prompt shown only until the first AI connects — first-run direction
    /// without nagging afterwards.
    private var firstRunNudge: some View {
        Label(model.t("services.firstrun"), systemImage: "bolt.horizontal.circle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.accent)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                .fill(Theme.accentSoft))
            .padding(.horizontal, Space.xs).padding(.bottom, Space.xs)
    }

    private func row(_ p: AIProvider) -> some View {
        let selected = model.selectedService == p && model.selectedTool == nil
        let connected = model.isConnected(p)
        // Connected providers show their declared plan as a subtitle (quiet context);
        // status is carried by a single dot, not a text label (scans down the column).
        return CoralRow(title: p.displayName,
                        subtitle: connected ? model.providerPlan(p) : nil,
                        selected: selected,
                        leading: { ProviderLogo(provider: p, size: 20, templateTint: p.tint) },
                        trailing: { statusDot(connected, stale: model.staleAuth.contains(p)) })
            .onTapGesture { model.selectedService = p; model.selectedTool = nil }
    }

    private func groupHeader(_ title: String, count: String? = nil) -> some View {
        HStack(spacing: Space.xs) {
            Text(title).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
            if let count {
                Text(count).font(.sfFieldLabel).foregroundStyle(.quaternary).tracking(0.6)
            }
            Spacer()
        }
        .padding(.horizontal, Space.xs).padding(.bottom, 2)
    }

    /// A 6pt status dot — success when live, AMBER when installed but the stored login looks
    /// expired/missing (reconnect needed), quiet reef when not found. Replaces the wordy
    /// per-row label so the whole column scans at a glance.
    private func statusDot(_ connected: Bool, stale: Bool = false) -> some View {
        let color: Color = !connected ? Color.secondary.opacity(0.4)
            : (stale ? Theme.warning : Theme.success)
        return Circle().fill(color)
            .frame(width: 6, height: 6)
            .padding(.trailing, 2)
            .help(model.t(!connected ? "provider.notFound"
                          : (stale ? "provider.reconnect" : "provider.connected")))
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

}

/// The roadmap vote affordance: a compact pill in a future-provider row. Coral-outlined
/// when un-voted, filled coral when voted (tap again to un-vote — honest, changeable).
/// No numeric count — we have no backend and won't fake a global tally.
private struct VotePill: View {
    @Environment(AppModel.self) private var model
    let voted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: voted ? "checkmark" : "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                Text(model.t(voted ? "future.voted" : "future.vote"))
                    .font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(voted ? .white : Theme.accent)
            .padding(.horizontal, Space.s).padding(.vertical, 4)
            .background(
                Capsule().fill(voted ? AnyShapeStyle(Theme.accent)
                                     : AnyShapeStyle(hovering ? Theme.accentSoft : Color.clear)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(voted ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(model.t(voted ? "future.voted" : "future.vote"))
    }
}

/// A wrapping row of tappable chips — the chats a provider is "Used by". Reef-inset
/// capsules that jump to the chat on tap.
private struct FlowChips: View {
    let items: [(id: Configuration.ID, name: String)]
    let onTap: (Configuration.ID) -> Void

    init(_ items: [(Configuration.ID, String)], onTap: @escaping (Configuration.ID) -> Void) {
        self.items = items.map { (id: $0.0, name: $0.1) }
        self.onTap = onTap
    }

    var body: some View {
        FlowLayout(spacing: Space.xs) {
            ForEach(items, id: \.id) { item in
                Button { onTap(item.id) } label: {
                    Text(item.name).font(.sfCaption2).lineLimit(1)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Space.s).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.insetBg))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A minimal left-to-right wrapping layout — chips flow to the next line when they'd
/// overflow the container width. (No dependency; small enough to keep local.)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
    @State private var showAdvanced = false
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
                usedByCard
                if connected { diagnoseCard }
                advancedDisclosure
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

    /// The screen's ONE hero surface: the connection status, tinted by state (green when
    /// connected, coral CTA when not) and elevated — a clear focal point instead of one of
    /// several equal cards (premium verdict A3).
    private var statusCard: some View {
        HStack(spacing: Space.m) {
            Image(systemName: connected ? "checkmark.circle.fill" : "bolt.horizontal.circle")
                .font(.system(size: 26))
                .foregroundStyle(connected ? Theme.success : Theme.accent)
            Text(model.t(connected ? "provider.connected" : "provider.notFound"))
                .font(.sfCardTitle).foregroundStyle(Theme.ink)
            Spacer(minLength: Space.s)
            if connected {
                // Already connected — offer a discreet re-auth (web sign-in).
                Button(model.t("provider.reconnect")) { connecting = true }
                    .buttonStyle(.plain).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                Button(model.t("provider.connect")) { connecting = true }
                    .buttonStyle(.moon)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .fill(connected ? Theme.success.opacity(0.08) : Theme.accentSoft).elevation(.e3))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder((connected ? Theme.success : Theme.accent).opacity(0.25), lineWidth: 1))
    }

    /// Where this provider is actually used — the chats bound to it (and, quietly, the
    /// saved teams with a role on it). Turns the config screen into a hub: each chat chip
    /// jumps straight to it. Empty state offers a one-tap "start a chat here".
    private var usedByCard: some View {
        let chats = model.configurations.filter { $0.provider == provider }
        let teamCount = model.savedTeams.filter { t in
            t.strategy.roles.contains { $0.provider == provider }
        }.count
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("provider.usedBy")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            if chats.isEmpty && teamCount == 0 {
                Text(model.t("provider.usedBy.empty", provider.displayName))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if connected {
                    Button(model.t("provider.usedBy.start", provider.displayName)) {
                        model.addConfiguration(provider: provider)
                    }
                    .buttonStyle(.moon).controlSize(.small)
                }
            } else {
                Text(usedBySummary(chatCount: chats.count, teamCount: teamCount))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                if !chats.isEmpty {
                    FlowChips(chats.prefix(6).map { ($0.id, $0.name.isEmpty ? model.t("chat.untitled") : $0.name) }) { id in
                        model.navSection = .chats
                        model.selectedConfigID = id
                    }
                }
            }
        }
        .card()
    }

    /// "3 chats · 2 teams" — only the non-zero parts, localized.
    private func usedBySummary(chatCount: Int, teamCount: Int) -> String {
        var parts: [String] = []
        if chatCount > 0 { parts.append(model.t("provider.usedBy.chats", chatCount)) }
        if teamCount > 0 { parts.append(model.t("provider.usedBy.teams", teamCount)) }
        return parts.joined(separator: " · ")
    }

    /// CLI binary + model + reasoning effort — decision-relevant only occasionally, so
    /// they live behind one "Advanced" disclosure instead of competing with the hero.
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: Space.l) {
                binaryCard
                if provider == .openai { codexModelCard }
                if provider.supportsReasoningEffort { reasoningEffortCard }
            }
            .padding(.top, Space.s)
        } label: {
            Text(model.t("provider.advanced")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
        }
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
