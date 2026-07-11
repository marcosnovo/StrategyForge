//
//  ChatView.swift
//  StrategyForge
//
//  The "work here" chat: after designing the strategy, talk to Claude directly.
//  Claude Code runs headless in the project's repo (honoring the generated
//  .claude/agents + CLAUDE.md), edits files directly, and streams its replies.
//  No code pane — just the conversation, like a focused agent chat.
//

import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Binding var showInspector: Bool
    @Binding var showSidebar: Bool
    /// Live configuration for header display (title/strategy/repo), re-passed by the
    /// parent so edits made in the config sheet reflect immediately.
    let config: Configuration
    /// The chat's engine, owned and cached by AppModel (`chatViewModel(for:)`) —
    /// the view only observes it. Plain `let` is fine: @Observable tracks reads.
    let vm: ChatViewModel
    @State private var editingTitle: String
    @Binding var showActivity: Bool
    @State private var showPreview = false
    @State private var agentFocus: AgentFocus?
    @FocusState private var inputFocused: Bool
    /// Bumps on each sent message to drive send haptics.
    @State private var sendPulse = 0
    /// Which assistant message just had its text copied (shows a ✓ for a moment).
    @State private var copiedMessageID: ChatMessage.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    /// True when this chat's engine CLI (Claude) isn't installed — offer one-tap setup.
    @State private var engineMissing = false
    @State private var showInstall = false
    @State private var isDropTargeted = false
    /// Confirmation before granting persistent full access.
    @State private var confirmAlwaysAllow = false
    @State private var showReport = false
    /// Code mode: a developer workspace (files/diffs) instead of plain chat.
    @State private var codeMode = false
    /// Token Saver: tips dismissed in this chat session, plus the transient
    /// "an attachment was just staged" flag that gates the convert tip.
    @State private var dismissedTips: Set<TokenSaverEngine.TipKind> = []
    @State private var justAttached = false
    /// Advisor-in-chat: the debounced recommendation computed from the draft of
    /// a brand-new chat, and whether the user waved the card away this session.
    @State private var advisorDismissed = false
    @State private var inlineAdvice: AdvisorEngine.Advice?
    @State private var adviceTask: Task<Void, Never>?
    /// Persisted, user-resizable width of the agent-activity panel.
    @AppStorage("col.activity") private var activityW = 320.0
    private let rename: (String) -> Void
    private let saveDraft: (String) -> Void

    init(config: Configuration, vm: ChatViewModel,
         showInspector: Binding<Bool> = .constant(false),
         showSidebar: Binding<Bool> = .constant(true),
         showActivity: Binding<Bool> = .constant(false),
         rename: @escaping (String) -> Void = { _ in },
         saveDraft: @escaping (String) -> Void = { _ in }) {
        self.config = config
        self.vm = vm
        self.rename = rename
        self.saveDraft = saveDraft
        _showInspector = showInspector
        _showSidebar = showSidebar
        _showActivity = showActivity
        _editingTitle = State(initialValue: config.name)
    }

    init(viewModel: ChatViewModel, showInspector: Binding<Bool> = .constant(false)) {
        self.config = viewModel.config
        self.vm = viewModel
        self.rename = { _ in }
        self.saveDraft = { _ in }
        _showInspector = showInspector
        _showSidebar = .constant(true)
        _showActivity = .constant(false)
        _editingTitle = State(initialValue: viewModel.config.name)
    }

    var body: some View {
        HStack(spacing: 0) {
            chatColumn
            if showActivity {
                ResizableDivider(
                    width: Binding(get: { CGFloat(activityW) }, set: { activityW = Double($0) }),
                    range: 260...560, sign: -1)
                AgentActivityPanel(vm: vm, focus: $agentFocus)
                    .frame(width: CGFloat(activityW))
            }
            if showActivity, let focus = agentFocus {
                SubagentDetailPanel(vm: vm, focus: focus) { agentFocus = nil }
                    .frame(width: 300)
            }
        }
        // NOTE: no implicit animation / transition here. These panels contain
        // continuously-redrawing TimelineViews (WorkingLogo, live diagram) over
        // materials; animating their insertion made the UI hang. Snap them in.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The chat is the protagonist: a clean, bright, near-white surface (not the
        // dull frosted gray) so the conversation feels open and modern.
        .background(Theme.columnBg)
        // Reflect an auto-generated title (set in AppModel after the first message).
        .onChange(of: config.name) { _, new in editingTitle = new }
        // Auto-open the panel the first time an agent starts working.
        .onChange(of: vm.isRunning) { _, running in
            if running && vm.timeline.isEmpty && !showActivity { showActivity = true }
        }
        // Proactively check the engine is installed (Claude), so the user is guided
        // to one-tap setup instead of hitting a technical error after sending.
        .task(id: config.provider) { await checkEngine() }
        .sheet(isPresented: $showInstall) {
            ProviderInstallSheet(provider: .claude) { Task { await checkEngine() } }
        }
        .sheet(isPresented: $showReport) {
            MissionReportView(
                title: config.name.isEmpty ? (vm.todos.first?.content ?? "") : config.name,
                strategyName: model.strategyDisplayName(config.strategy),
                agents: MissionReport.agentLines(strategy: config.strategy, timeline: vm.timeline),
                tokens: vm.totalTokens,
                costUSD: vm.totalCostUSD,
                elapsed: vm.turnStartedAt.map { activityElapsed(from: $0, to: vm.timeline.last?.at ?? Date()) } ?? "",
                outcome: vm.messages.last(where: { $0.role == .assistant })?.text ?? ""
            )
            .environment(model)
        }
        // Preserve unsent text when leaving this chat.
        .onDisappear { saveDraft(vm.input) }
    }

    /// A friendly card shown when the chat's engine CLI isn't installed yet.
    private var engineMissingCard: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("chat.engineMissing")).font(.sfCallout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Button(model.t("chat.locate")) { locateClaude() }
                .controlSize(.small)
            Button(model.t("chat.install")) { showInstall = true }
                .controlSize(.small).buttonStyle(.moon)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft)
    }

    /// Honest note when the team mixes providers that don't run yet.
    private var mixedProvidersStrip: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.warning).font(.system(size: 11))
            Text(model.t("chat.mixedProviders")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Button { vm.mixedProvidersNote = false } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(model.t("common.done"))
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.10))
    }

    private func checkEngine() async {
        guard config.provider == .claude else { engineMissing = false; return }
        let name = model.settings.claudeBinary
        let path = await Task.detached { ClaudeRunner.resolveBinary(name) }.value
        engineMissing = (path == nil)
    }

    /// Let the user point at an existing `claude` binary if auto-detection missed it.
    private func locateClaude() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.settings.claudeBinary = url.path
        model.save()
        Task { await checkEngine() }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            header
            if vm.isRunning { runningProgressBar }
            if codeMode { CodeModeView(vm: vm) } else { messagesList }
            if engineMissing { engineMissingCard }
            if vm.mixedProvidersNote { mixedProvidersStrip }
            if !vm.deniedTools.isEmpty && !vm.isRunning { deniedStrip }
            if !vm.editedFiles.isEmpty { changedFilesStrip }
            if let error = vm.errorText { errorBanner(error) }
            if advisorCardVisible, let advice = inlineAdvice {
                AdvisorInlineCard(
                    advice: advice,
                    strategyName: model.strategyDisplayName(advice.strategy),
                    onApplyTeam: {
                        model.applyTemplate(advice.strategy, to: config.id)
                        withAnimation { advisorDismissed = true }
                    },
                    onCreateLoop: { createLoop(from: advice) },
                    onDismiss: { withAnimation { advisorDismissed = true } })
                    .padding(.horizontal, Space.m)
                    .padding(.top, Space.s)
            }
            // At most one coach banner at a time: the Advisor card wins.
            if let tip = saverTip, !advisorCardVisible {
                TokenSaverBanner(tip: tip,
                                 onAction: { saverAction(tip) },
                                 onDismiss: { dismissedTips.insert(tip.kind) })
                    .padding(.horizontal, Space.m)
                    .padding(.top, Space.s)
            }
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: vm.deniedTools)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: vm.editedFiles.count)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: saverTip)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: inlineAdvice)
        // Arm the convert tip on the render right after an attachment is staged.
        .onChange(of: vm.attachments.count) { old, new in
            justAttached = new > old
        }
        // Refresh the Advisor's suggestion from the draft, debounced so it never
        // recomputes on every keystroke. Only while composing the FIRST message.
        .onChange(of: vm.input) { _, draft in
            adviceTask?.cancel()
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard vm.messages.isEmpty, !advisorDismissed, trimmed.count >= 25 else {
                withAnimation { inlineAdvice = nil }
                return
            }
            adviceTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                // advise(task:) is pure and fast — fine on the main actor.
                withAnimation { inlineAdvice = AdvisorEngine.advise(task: draft) }
            }
        }
        // Drop files anywhere on the chat to attach them for review.
        .dropDestination(for: URL.self) { urls, _ in handleDrop(urls); return true } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.corner)
                    .strokeBorder(Theme.accentHover, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                    .background(Theme.accentHover.opacity(0.10))
                    .overlay(
                        Label(model.t("chat.dropHint"), systemImage: "paperclip.badge.plus")
                            .font(.sfCardTitle).foregroundStyle(Theme.accentHover)
                            .symbolEffect(.bounce, value: isDropTargeted)
                            .padding(Space.m)
                            .background(.regularMaterial, in: Capsule())
                    )
                    .padding(Space.s).allowsHitTesting(false)
            }
        }
    }

    // MARK: - Advisor in chat

    /// The inline Advisor card shows only while composing the first message of
    /// a fresh chat — and it displaces the Token Saver banner (never stack two).
    private var advisorCardVisible: Bool {
        vm.messages.isEmpty && !advisorDismissed && inlineAdvice != nil
    }

    /// Hand this chat over to the Loop Builder, prefilled from an advice.
    private func createLoop(from advice: AdvisorEngine.Advice) {
        let plan = LoopPlan(name: config.name.isEmpty ? loopNameFromSource() : config.name,
                            kind: advice.loopKind,
                            goal: advice.goalSuggestion,
                            workerModel: advice.model,
                            repoPath: config.repoPath,
                            repoBookmark: config.repoBookmark)
        LoopStore.shared.addLoop(prefill: plan)
        model.navSection = .loops
        model.flashSuccess(model.t("loop.createdFromAdvice"))
    }

    /// A loop name for an untitled chat, inferred from the first user message or
    /// the unsent draft (same helper AppModel uses to auto-title chats).
    private func loopNameFromSource() -> String {
        let source = vm.messages.first(where: { $0.role == .user })?.text
            ?? vm.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        return model.titleFromMessage(source)
    }

    /// Header-menu path: draft the loop goal from the first user message (or
    /// the unsent draft) via the Advisor, then jump to the Loop Builder.
    private func createLoopFromChat() {
        let source = vm.messages.first(where: { $0.role == .user })?.text
            ?? (vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vm.input)
        if let source {
            createLoop(from: AdvisorEngine.advise(task: source))
        } else {
            let plan = LoopPlan(name: config.name,
                                repoPath: config.repoPath,
                                repoBookmark: config.repoBookmark)
            LoopStore.shared.addLoop(prefill: plan)
            model.navSection = .loops
            model.flashSuccess(model.t("loop.createdFromAdvice"))
        }
    }

    // MARK: - Token Saver

    /// The single most valuable saver tip for the current state (nil while running).
    private var saverTip: TokenSaverEngine.Tip? {
        guard !vm.isRunning else { return nil }
        let lastExt = vm.attachments.last?.url.pathExtension.lowercased() ?? ""
        let signals = TokenSaverEngine.Signals(
            messageCount: vm.messages.count,
            cumulativeTokens: vm.totalTokens,
            lastUserMessages: vm.messages.filter { $0.role == .user }.suffix(3).map(\.text),
            justAttachedFile: justAttached,
            attachmentIsImageOrPDF: ["pdf", "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(lastExt),
            orchestratorModel: config.strategy.orchestrator?.model,
            draft: vm.input)
        return TokenSaverEngine.tip(for: signals, dismissed: dismissedTips)
    }

    private func saverAction(_ tip: TokenSaverEngine.Tip) {
        switch tip.kind {
        case .summarizeRestart:
            model.startFreshChat(from: config.id, summary: carryForwardSummary())
        case .newTopicNewChat:
            model.startFreshChat(from: config.id)
        case .convertAttachment:
            convertStagedPDFs()
        default:
            break
        }
        dismissedTips.insert(tip.kind)
    }

    /// A tiny extractive summary (first ask + last answer) seeded into the fresh
    /// chat's draft: context carries forward for a few hundred tokens instead of
    /// a full history re-read.
    private func carryForwardSummary() -> String {
        let firstAsk = vm.messages.first(where: { $0.role == .user })?.text ?? ""
        let lastAnswer = vm.messages.last(where: { $0.role == .assistant })?.text ?? ""
        var lines = [model.t("saver.summary.header")]
        if !firstAsk.isEmpty { lines.append("• \(firstAsk.prefix(300))") }
        if !lastAnswer.isEmpty { lines.append("• \(lastAnswer.prefix(300))") }
        return lines.joined(separator: "\n")
    }

    /// Replace staged PDF attachments with their extracted plain text (10–20×
    /// cheaper for Claude to read). Images stay as-is — the tip's advice there
    /// is to crop before attaching.
    private func convertStagedPDFs() {
        Task {
            for i in vm.attachments.indices {
                guard vm.attachments.indices.contains(i) else { break }
                let att = vm.attachments[i]
                guard att.url.pathExtension.lowercased() == "pdf" else { continue }
                if let txt = await AttachmentConverter.extractPDFText(att.url) {
                    vm.attachments[i] = Attachment(name: att.name, url: txt)
                }
            }
            justAttached = false
        }
    }

    /// Convert dropped files (Office docs → text) and stage them as attachments.
    private func handleDrop(_ urls: [URL]) {
        for url in urls {
            Task {
                let readable = await AttachmentConverter.convert(url)
                let att = Attachment(name: url.lastPathComponent, url: readable)
                if !vm.attachments.contains(where: { $0.name == att.name }) {
                    vm.attachments.append(att)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                // The chat title — the H1, editable inline.
                TextField(model.t("chat.untitled"), text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.sfCardTitle)
                    .onSubmit { rename(editingTitle) }

                HStack(spacing: Space.s) {
                    providerStack
                    // The chat USES a team: pick a saved one, tweak this chat's copy,
                    // or jump to the Team library to manage them.
                    Menu {
                        if !model.savedTeams.isEmpty {
                            Section(model.t("team.library.apply")) {
                                ForEach(model.savedTeams) { team in
                                    Button(team.name) { model.applyTeam(team, to: config.id) }
                                }
                            }
                        }
                        Button(model.t("chat.customizeTeam")) { showInspector = true }
                        Button(model.t("team.manage")) { model.navSection = .team }
                        Divider()
                        Button(model.t("chat.createLoop")) { createLoopFromChat() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.strategyDisplayName(config.strategy))
                                .font(.sfCaption2.weight(.medium))
                                .foregroundStyle(Theme.accent)
                            // Explicit disclosure cue: the capsule is a menu, not a label.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.18)).interactive(),
                                     in: .capsule)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(model.t("chat.teamMenu.help"))

                    if let path = config.repoPath, !path.isEmpty {
                        Text(model.t("chat.subtitle", (path as NSString).lastPathComponent))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(model.t("chat.scratch"))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            // Persistent full-access indicator — visible and one-tap revocable, so
            // "allow always" is never a silent, irreversible state.
            if vm.elevatedPermissions {
                Button { vm.disableElevation() } label: {
                    Label(model.t("chat.fullAccessOn"), systemImage: "checkmark.shield.fill")
                        .font(.sfCaption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warning.opacity(0.18)))
                        .foregroundStyle(Theme.warning)
                }
                .buttonStyle(.plain)
                .help(model.t("chat.fullAccessOn.help"))
            }
            // Context weight: the token count colored by how heavy every further
            // re-read of this conversation has become (Token Saver).
            HStack(spacing: 6) {
                ContextWeightPill(tokens: vm.totalTokens)
                if vm.totalCostUSD > 0 {
                    Text(String(format: "$%.2f", vm.totalCostUSD))
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }
            }
            // Mission report — the shareable summary of the finished run.
            if vm.hasFinishedActivity {
                Button { showReport = true } label: {
                    Image(systemName: "flag.checkered")
                }
                .buttonStyle(.borderless)
                .help(model.t("report.open"))
                .accessibilityLabel(model.t("report.title"))
            }
            if codeModeEligible {
                Button { codeMode.toggle() } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(codeMode ? Theme.accent : .secondary)
                }
                .buttonStyle(.borderless)
                .help(model.t("chat.codeMode.help"))
                .accessibilityLabel(model.t("chat.codeMode"))
            }

            Button {
                showActivity.toggle()
                if !showActivity { agentFocus = nil }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .foregroundStyle(showActivity ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(model.t("chat.activity.help"))
            .accessibilityLabel(model.t("chat.activity"))

            Button { showInspector = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(model.t("inspector.toggle"))
            .accessibilityLabel(model.t("chat.settings"))
        }
        .padding(Space.m)
        .background {
            Rectangle().fill(.bar)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
        }
        .zoomWindowOnDoubleClick()
        .zIndex(1)
    }

    /// Progress for the running turn. Determinate from the agent's task list
    /// (real completed/total) in the shared loop visual language (ProgressDotsRow),
    /// else a slim indeterminate bar so it never feels stuck.
    private var runningProgressBar: some View {
        VStack(spacing: 0) {
            if let p = vm.taskProgress, p.total > 0 {
                HStack(spacing: Space.s) {
                    ProgressDotsRow(done: p.done, total: p.total)
                    Text(model.t("chat.tasksProgress", p.done, p.total))
                        .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                        .monospacedDigit().fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.m).padding(.vertical, 5)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    .padding(.horizontal, Space.m).padding(.vertical, 5)
            }
            Divider()
        }
        .background(.bar)
    }

    /// Which AI back-end this chat runs on — a menu to switch providers.
    /// A compact, Refil-style row of provider avatars: connected ones are tappable
    /// to switch this chat's back-end (active gets a ring); disconnected ones are
    /// dimmed and lead to Connect. Replaces the old text pill (and fixes the giant
    /// logo that a Menu label rendered from a resizable image).
    /// The distinct providers the mounted team actually uses (union of the roles'
    /// providers), in a stable order — so the header only lists what's in play.
    private var teamProviders: [AIProvider] {
        let used = Set(config.strategy.roles.map(\.provider))
        let ordered = AIProvider.allCases.filter { used.contains($0) }
        return ordered.isEmpty ? [config.provider] : ordered
    }

    private var providerStack: some View {
        HStack(spacing: -6) {
            ForEach(teamProviders) { p in
                let connected = model.isConnected(p)
                Button {
                    if connected { model.setProvider(config.id, p) }
                    else { model.selectedService = p; model.navSection = .services }
                } label: {
                    ProviderAvatar(provider: p, size: 24, active: config.provider == p && connected)
                        .opacity(connected ? 1 : 0.45)
                        .grayscale(connected ? 0 : 0.7)
                }
                .buttonStyle(.plain)
                .zIndex(config.provider == p ? 1 : 0)
                .help(connected ? p.displayName : "\(p.displayName) — \(model.t("provider.locked"))")
                .accessibilityLabel(connected ? p.displayName : "\(p.displayName) — \(model.t("provider.locked"))")
            }
        }
        .padding(.trailing, Space.xs)
        .fixedSize()
    }

    /// Code mode is offered only when the chat targets a real folder on disk.
    private var codeModeEligible: Bool { !(config.repoPath ?? "").isEmpty }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copy an assistant message and flash a ✓ on its button for ~1.5s.
    private func copy(_ message: ChatMessage) {
        copyToClipboard(message.text)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copiedMessageID = message.id }
        let id = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageID == id {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copiedMessageID = nil }
            }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.messageSpacing) {
                    if vm.messages.isEmpty { emptyState }
                    ForEach(vm.messages) { message in
                        bubble(message,
                               isStreaming: vm.isRunning
                                   && message.role == .assistant
                                   && message.id == vm.messages.last?.id)
                            .id(message.id)
                            // Extra breathing room above each new turn (user message),
                            // so a turn reads as a unit distinct from the previous reply.
                            .padding(.top, message.role == .user
                                     && message.id != vm.messages.first?.id ? Theme.turnGap : 0)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .opacity.combined(with: .offset(
                                    x: message.role == .user ? 20 : -12, y: 8)),
                                removal: .opacity))
                    }
                    if vm.isRunning {
                        activityRow.id("activity")
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: vm.messages.count)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: vm.isRunning)
            }
            .onChange(of: vm.messages.last?.text) { scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            // Ambient aurora behind the empty canvas. ALWAYS mounted (never
            // structurally inserted/removed — the documented hang pattern);
            // once the conversation starts, intensity drops to 0 (the component
            // then renders no TimelineView at all — free) while the outer
            // opacity fades the last frame out. Static under Reduce Motion.
            .background {
                AuroraBackground(intensity: vm.messages.isEmpty ? 0.8 : 0)
                    .opacity(vm.messages.isEmpty ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45),
                               value: vm.messages.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, isStreaming: Bool) -> some View {
        if message.role == .user {
            // User: compact bubble on the right.
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.sfBodyM)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .foregroundStyle(Theme.onAccent)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous).fill(Theme.accent))
                    .contextMenu { copyButton(message.text) }
            }
        } else {
            // Assistant: a soft rounded bubble (reference-style), with an avatar.
            HStack(alignment: .top, spacing: Space.s) {
                Group {
                    if isStreaming {
                        WorkingLogo(size: 20)
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.accentSoft))
                    }
                }
                .frame(width: 28, height: 28)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownView(text: message.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                        .background(RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous)
                            .fill(Theme.insetBg))
                        // While tokens stream in, a soft highlight sweeps the bubble
                        // so the reply visibly feels alive. Off under Reduce Motion.
                        .shimmer(isStreaming && !reduceMotion)
                        .contextMenu { copyButton(message.text) }
                    if !message.text.isEmpty {
                        let copied = copiedMessageID == message.id
                        Button { copy(message) } label: {
                            Label(copied ? model.t("chat.copied") : model.t("chat.copy"),
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.sfCaption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isStreaming ? AnyShapeStyle(.quaternary)
                                         : (copied ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary)))
                        .disabled(isStreaming)
                        .padding(.leading, Space.xs)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                Spacer(minLength: 32)
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            copyToClipboard(text)
        } label: {
            Label(model.t("chat.copy"), systemImage: "doc.on.doc")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            strategyHook
                .staggeredAppear(index: 0)
            Text(model.t("chat.empty"))
                .font(.sfCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(["chat.suggest1", "chat.suggest2", "chat.suggest3"].enumerated()),
                        id: \.element) { index, key in
                    Button { vm.input = model.t(key) } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: "arrow.up.forward.square").foregroundStyle(Theme.accent)
                            Text(model.t(key)).font(.sfCallout).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                            .fill(Theme.insetBg)
                            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                                .strokeBorder(Theme.hairline, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                    .staggeredAppear(index: index)
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The quiet dot-field identity drifting at the trailing edge (the aurora
        // wash lives on the always-mounted messagesList background, per the hang
        // note in `body`). The transaction guard makes this TimelineView's
        // removal SNAP when the first message lands — its structural removal
        // must never animate (see the postmortem comment in `body`).
        .background(alignment: .topTrailing) {
            if !reduceMotion {
                ParticleField(density: 50, reactive: true)
                    .frame(width: 280, height: 280)
                    .opacity(0.35)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
    }

    /// The differentiator, front and center on an empty chat: this chat is driven
    /// by the team you designed — show it (diagram + name + size + what it's for).
    private var strategyHook: some View {
        let teammates = config.strategy.subagentRoles.reduce(0) { $0 + max(1, $1.count) }
        return HStack(spacing: Space.m) {
            StrategyThumbnail(strategy: config.strategy)
                .frame(width: 104, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                // A subtle coral breath on the team diagram — the hero of the empty
                // state — quiet enough to invite, stilled under Reduce Motion.
                .breathingGlow(color: Theme.coral, enabled: !reduceMotion)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("chat.team.ready"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Text(model.strategyDisplayName(config.strategy)).font(.sfCardTitle)
                Text(teammates == 0 ? model.t("chat.team.solo") : model.t("chat.team.count", teammates))
                    .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    .help(model.t("glossary.worker"))
                Text(model.strategyGoodFor(config.strategy))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: 560, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.innerCorner))
    }

    private var activityRow: some View {
        HStack(spacing: Space.s) {
            WorkingLogo(size: 18)
            if let sub = vm.activeSubagent {
                // Show the strategy at work: which teammate the orchestrator called.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                    Text(model.t("chat.delegating", sub)).font(.sfCaption2.weight(.medium))
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(vm.activity.isEmpty
                     ? model.t("chat.thinking")
                     : model.t("chat.using", Array(vm.activity.suffix(3)).joined(separator: ", ")))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
    }

    /// A strip of the files the agent produced — each a chip you can preview or
    /// download straight from the chat.
    private var changedFilesStrip: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(model.t("chat.changedFiles", vm.editedFiles.count))
                .font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                .fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(vm.editedFiles, id: \.self) { path in fileChip(path) }
                }
            }
            Button { showPreview = true } label: {
                Image(systemName: "eye").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .help(model.t("filepreview.title"))
            .accessibilityLabel(model.t("filepreview.title"))
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hairline.opacity(0.6))
        .sheet(isPresented: $showPreview) {
            DocumentPreviewSheet(files: vm.editedFiles)
        }
    }

    /// One produced file: name + a one-click download.
    private func fileChip(_ path: String) -> some View {
        HStack(spacing: 4) {
            Text((path as NSString).lastPathComponent)
                .font(.sfCaption2).lineLimit(1)
            Button { downloadFile(path) } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .help(model.t("chat.download"))
            .accessibilityLabel("\(model.t("chat.download")): \((path as NSString).lastPathComponent)")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
    }

    /// Save a copy of a produced file wherever the user chooses.
    private func downloadFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: dest)   // replacing is fine; absence isn't an error
            try FileManager.default.copyItem(at: url, to: dest)
            model.flashSuccess(model.t("chat.fileSaved", url.lastPathComponent))
        } catch {
            model.flashFailure(model.t("banner.writeFailed", error.localizedDescription))
        }
    }

    /// Shown after a run that was blocked by permission denials: what was blocked
    /// and a one-click "allow all & retry".
    private var deniedStrip: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.warning).font(.system(size: 12))
                    .symbolEffect(.pulse, options: .repeating)
                Text(model.t("chat.denied.title")).font(.sfCallout.weight(.semibold))
                Spacer()
            }
            // What was blocked, and what each of those tools actually does.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(vm.deniedTools.prefix(4).enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry).font(.sfCaption2.weight(.medium)).foregroundStyle(.primary)
                        Text("— \(explainTool(entry))")
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: Space.s) {
                Spacer()
                // "Allow always" is powerful (persistent full access) → make it the
                // secondary, confirmed action; the safe one-shot retry is primary.
                Button { confirmAlwaysAllow = true } label: {
                    Label(model.t("chat.allowAlways"), systemImage: "checkmark.shield")
                }
                .controlSize(.small).buttonStyle(.bordered)
                .help(model.t("chat.allowAlways.help"))
                .confirmationDialog(model.t("chat.allowAlways.confirmTitle"),
                                    isPresented: $confirmAlwaysAllow, titleVisibility: .visible) {
                    Button(model.t("chat.allowAlways"), role: .destructive) {
                        vm.retryAllowingAll(persistElevation: true)
                    }
                    Button(model.t("common.cancel"), role: .cancel) {}
                } message: {
                    Text(model.t("chat.allowAlways.confirmMsg"))
                }
                Button { vm.retryAllowingAll(persistElevation: false) } label: {
                    Text(model.t("chat.allowOnce"))
                }
                .controlSize(.small).buttonStyle(.moon)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// One-line, plain explanation of what a denied tool does.
    private func explainTool(_ entry: String) -> String {
        let name = entry.split(separator: " ").first.map(String.init) ?? entry
        let known = ["Bash", "Write", "Edit", "MultiEdit", "Read", "WebFetch", "WebSearch"]
        return model.t(known.contains(name) ? "perm.explain.\(name)" : "perm.explain.default")
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.10))
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !vm.attachments.isEmpty { attachmentChips }
            HStack(spacing: Space.s) {
            // Attach files for Claude to review.
            Button {
                pickAttachments()
            } label: {
                Image(systemName: "paperclip").font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help(model.t("chat.attach"))
            .accessibilityLabel(model.t("chat.attach"))

            TextField(model.t("chat.placeholder"),
                      text: Bindable(vm).input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(Space.s)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.innerCorner))
                // Focus reads as light, not weight: a fine coral ring plus a faint
                // outer glow on the glass while composing; quiet when unfocused.
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.innerCorner)
                        .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.5)
                        .opacity(inputFocused ? 1 : 0)
                )
                .shadow(color: Theme.accent.opacity(inputFocused ? 0.18 : 0), radius: 8)
                .focused($inputFocused)
                .animation(.easeOut(duration: 0.18), value: inputFocused)
                .onSubmit { send() }
                // Up arrow on an empty field recalls the last message to edit/resend.
                .onKeyPress(.upArrow) {
                    guard vm.input.isEmpty,
                          let last = vm.messages.last(where: { $0.role == .user }) else { return .ignored }
                    vm.input = last.text
                    return .handled
                }

            if vm.isRunning {
                Button { vm.stop() } label: {
                    Label(model.t("chat.stop"), systemImage: "stop.fill")
                }
                .controlSize(.large)
            } else {
                Button { send() } label: {
                    Label(model.t("chat.send"), systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.moon)
                .controlSize(.large)
                .disabled(!vm.canSend || engineMissing)
                .keyboardShortcut(.return, modifiers: .command)
            }
            }
        }
        .padding(Space.m)
        .background(.bar)
        .sensoryFeedback(.impact(weight: .medium), trigger: sendPulse)
    }

    /// Chips for staged attachments, each removable.
    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(vm.attachments) { att in
                    HStack(spacing: 4) {
                        Image(systemName: "doc").font(.system(size: 9))
                        Text(att.name).font(.sfCaption2).lineLimit(1)
                        Button { vm.attachments.removeAll { $0.id == att.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = model.t("chat.attach")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            // Convert Office docs to text so Claude can read them; images/PDF/code
            // pass through. Append when ready.
            Task {
                let readable = await AttachmentConverter.convert(url)
                let att = Attachment(name: url.lastPathComponent, url: readable)
                if !vm.attachments.contains(where: { $0.name == att.name }) {
                    vm.attachments.append(att)
                }
            }
        }
    }

    private func send() {
        guard vm.canSend else { return }
        sendPulse += 1          // tactile confirmation the message left
        vm.send()
        saveDraft("")           // sent → clear the persisted draft
        inputFocused = true     // keep the composer focused for the next turn
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: (any Hashable)? = vm.isRunning ? "activity" : vm.messages.last?.id
        guard let target else { return }
        if reduceMotion {
            proxy.scrollTo(AnyHashable(target), anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(AnyHashable(target), anchor: .bottom) }
        }
    }
}

private struct ChatPreviewHost: View {
    var body: some View {
        let vm = ChatViewModel(
            config: Configuration(name: "Demo", strategy: StrategyLibrary.orchestratorWorkers(),
                                  repoPath: "/Users/me/Projects/my-app"),
            binary: "claude")
        vm.messages = [
            .init(role: .user, text: "Add a dark mode toggle and update the tests."),
            .init(role: .assistant, text: "I'll add a `colorScheme` toggle to **Settings**, thread it through the theme, and update the snapshot tests. Starting now…"),
        ]
        return ChatView(viewModel: vm)
            .environment(AppModel())
            .tint(Theme.accent)
    }
}

#Preview("Chat") { ChatPreviewHost() }
#Preview("Chat (Dark)") { ChatPreviewHost().preferredColorScheme(.dark) }
