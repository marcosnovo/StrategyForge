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
    @Environment(AuthModel.self) private var auth
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
    /// Reveal the composer's mode/effort/context controls before the first message. They
    /// appear automatically once a chat has any messages; on a brand-new chat the box stays
    /// clean (ChatGPT-like) with a small "…" to open them on demand.
    @State private var showComposerControls = false
    /// Dismiss the "run this as a loop?" contextual suggestion for this session.
    @State private var loopSuggestDismissed = false
    /// Dismiss the "attach a folder" (work-in-repo) contextual suggestion for this session.
    @State private var repoSuggestDismissed = false
    /// Drives the "reconnect & retry" sheet when a turn fails with an auth error.
    @State private var reconnecting = false
    /// Code mode: a developer workspace (files/diffs) instead of plain chat.
    @State private var codeMode = false
    /// Token Saver: tips dismissed in this chat session, plus the transient
    /// "an attachment was just staged" flag that gates the convert tip.
    @State private var dismissedTips: Set<TokenSaverEngine.TipKind> = []
    @State private var justAttached = false
    /// Advisor-in-chat: the debounced recommendation computed from the draft of
    /// a brand-new chat, and whether the user waved the card away this session.
    @State private var advisorDismissed = false
    /// Cost/quality options for the first message (Economy · Recommended · Max) and
    /// which one the user picked (defaults to the balanced recommendation).
    @State private var inlineTiers: [AdvisorEngine.Tier] = []
    @State private var selectedTierID = "balanced"
    @State private var adviceTask: Task<Void, Never>?
    /// Follow-up prompts: the per-prompt "maybe switch the assignee" chip was waved away
    /// for the current draft. Resets when a new turn starts so each prompt gets a fresh,
    /// non-nagging suggestion.
    @State private var suggestionDismissed = false
    /// @-mention autocomplete: the repo's file list (loaded once per repo) and the
    /// current matches for the `@token` being typed.
    @State private var allRepoFiles: [String] = []
    @State private var mentionMatches: [String] = []
    /// Effort popover (Faster ↔ Smarter) visibility.
    @State private var showEffort = false
    /// Working-branch context bar: the branch + its ±diff, and any open PR.
    @State private var branchStat: CodeGit.BranchStat?
    @State private var prInfo: GitHubCLI.PRInfo?
    /// Slash-command palette matches for the current `/token`.
    @State private var slashMatches: [SlashCommand] = []
    /// Artifact viewer: the blocks to show and whether the sheet is open.
    @State private var shownArtifacts: [Artifact] = []
    @State private var showArtifacts = false
    /// Persisted, user-resizable width of the agent-activity panel.
    @AppStorage("col.activity") private var activityW = 320.0
    /// Width of the right-side Code workspace panel (files/diffs/terminal/git). Wider
    /// than the activity panel since it hosts a full developer view.
    @AppStorage("col.code") private var codeW = 520.0
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
            // Code Mode opens as the RIGHT-side panel (the chat stays put on the left)
            // rather than replacing the conversation. It takes precedence over the
            // activity panel while open.
            if codeMode {
                ResizableDivider(
                    width: Binding(get: { CGFloat(codeW) }, set: { codeW = Double($0) }),
                    range: 380...900, sign: -1)
                CodeModeView(vm: vm)
                    .frame(width: CGFloat(codeW))
            } else if showActivity {
                ResizableDivider(
                    width: Binding(get: { CGFloat(activityW) }, set: { activityW = Double($0) }),
                    range: 260...560, sign: -1)
                AgentActivityPanel(vm: vm, focus: $agentFocus,
                                   previewStrategy: advisorPreviewStrategy, previewLabel: advisorPreviewLabel,
                                   previewReason: advisorPreviewReason)
                    .frame(width: CGFloat(activityW))
                if let focus = agentFocus {
                    SubagentDetailPanel(vm: vm, focus: focus) { agentFocus = nil }
                        .frame(width: 300)
                }
            }
        }
        // NOTE: no implicit animation / transition here. These panels contain
        // continuously-redrawing TimelineViews (WorkingLogo, live diagram) over
        // materials; animating their insertion made the UI hang. Snap them in.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Translucent, tinted to the app's neutral surface color — the whole app shares
        // one glassy background (chat, side columns and activity panel all match).
        .translucentColumn()
        // Reflect an auto-generated title (set in AppModel after the first message).
        .onChange(of: config.name) { _, new in editingTitle = new }
        // Auto-open the panel the first time an agent starts working.
        .onChange(of: vm.isRunning) { _, running in
            // Don't split attention on the FIRST run — a newcomer should get a clean,
            // single-column first answer. Auto-open the activity panel only once they've
            // seen a completed run before (history non-empty). The header toggle still works.
            if running && vm.timeline.isEmpty && !showActivity && !vm.history.isEmpty { showActivity = true }
        }
        // Proactively check the engine is installed (Claude), so the user is guided
        // to one-tap setup instead of hitting a technical error after sending.
        .task(id: config.provider) { await checkEngine() }
        // Opened from the Code launcher → drop straight into the workspace once.
        .onAppear {
            if model.openInCodeMode == config.id {
                codeMode = true
                model.openInCodeMode = nil
            }
            model.clearAttention(config.id)   // the user is now looking at it
        }
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
                outcome: vm.messages.last(where: { $0.role == .assistant })?.text ?? "",
                // Actionable tuning hints from the run that just finished (the newest
                // persisted turn); empty when there's no history yet.
                retune: vm.history.last.map { RunAnalysis.retune(turn: $0, strategy: config.strategy) } ?? []
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
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.warningText).font(.system(size: 11))
            Text(model.t("chat.mixedProviders")).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Button { vm.mixedProvidersNote = false } label: {
                Image(systemName: "xmark").scaledFont(9)
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
        // The cached ChatViewModel captured the OLD binary path at init — drop it
        // (when idle) so the next turn actually uses the binary just located.
        if !vm.isRunning { model.invalidateChatVM(config.id) }
        Task { await checkEngine() }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            header
            // Only the MEANINGFUL determinate progress (the agent's own task list)
            // sits under the header; the old indeterminate "thinking" line was noise
            // and duplicated the activity panel, so it's gone.
            if vm.isRunning, let p = vm.taskProgress, p.total > 0 { runningProgressBar }
            // The chat always stays here; Code Mode now opens in the right-side panel
            // (see body) instead of replacing the conversation.
            messagesList
            // STATE strips keep their tinted treatment — these are things to resolve, not
            // suggestions. Color is reserved for state (design review, wave B).
            if engineMissing { engineMissingCard }
            if vm.mixedProvidersNote { mixedProvidersStrip }
            if !vm.deniedTools.isEmpty && !vm.isRunning { deniedStrip }
            if !vm.editedFiles.isEmpty { changedFilesStrip }
            if let error = vm.errorText { errorBanner(error) }
            // SUGGESTIONS collapse to ONE neutral coach at a time: the rich advisor card,
            // else a single CoachChip (team-fit / loop / repo), else a saving tip.
            if advisorCardVisible { advisorCard }
            coachSlot
            if let tip = saverTip, !advisorCardVisible, !hasCoachSuggestion {
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: inlineTiers)
        // Arm the convert tip on the render right after an attachment is staged.
        .onChange(of: vm.attachments.count) { old, new in
            justAttached = new > old
        }
        // A new turn gives each prompt a fresh, non-nagging assignee suggestion.
        .onChange(of: vm.messages.count) { suggestionDismissed = false }
        // Refresh the Advisor's suggestion from the draft, debounced so it never
        // recomputes on every keystroke. Only while composing the FIRST message.
        .onChange(of: vm.input) { _, draft in
            adviceTask?.cancel()
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            // Compute for the FIRST message (full card) AND for follow-up prompts (compact
            // suggestion chip) — the best-suited strategy can differ per prompt in a chat.
            guard trimmed.count >= 25, !vm.isRunning else {
                withAnimation { inlineTiers = [] }
                return
            }
            adviceTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                // Same on-device-AI path the first turn will apply, as three cost/
                // quality options — so the card matches what actually runs (falls back
                // to the deterministic engine when Apple Intelligence is unavailable).
                let tiers = await AdvisorEngine.adviseTiers(task: draft, connected: model.connectedProviders,
                                                            deprioritize: model.deprioritizedProviders,
                                                            modelLocked: model.modelLockedProviders)
                guard !Task.isCancelled else { return }
                // Telemetry: log the recommended (balanced) tier that the user is shown.
                if let balanced = tiers.first(where: { $0.id == "balanced" }) ?? tiers.first {
                    Analytics.logRecommendation(balanced.advice, task: draft,
                                                connected: model.connectedProviders,
                                                deprioritized: model.deprioritizedProviders)
                }
                withAnimation {
                    inlineTiers = tiers
                    if !tiers.contains(where: { $0.id == selectedTierID }) { selectedTierID = "balanced" }
                }
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
                        Label(model.t("chat.dropHint"), systemImage: "paperclip")
                            .font(.sfCardTitle).foregroundStyle(Theme.accentHover)
                            .symbolEffect(.bounce, value: isDropTargeted)
                            .padding(Space.m)
                            .background(.regularMaterial, in: Capsule())
                    )
                    .padding(Space.s).allowsHitTesting(false)
            }
        }
        // The finish celebration was moved out of the center of the screen: it now
        // plays as a discreet sphere-resolve on the finishing chat's sidebar thumbnail
        // (see SidebarView), so it never covers the conversation.
    }

    // MARK: - Advisor in chat

    /// The inline recommendation card (Economy · Recommended · Max), extracted so the
    /// chat column stays simple enough for the type-checker.
    private var advisorCard: some View {
        AdvisorInlineCard(
            tiers: inlineTiers,
            selectedID: selectedTierID,
            onSelectTier: { id in withAnimation(.easeOut(duration: 0.15)) { selectedTierID = id } },
            onApplyTeam: {
                if let advice = selectedTier?.advice { model.applyTemplate(advice.strategy, to: config.id) }
                withAnimation { advisorDismissed = true }
            },
            onCreateLoop: { if let a = selectedTier?.advice { createLoop(from: a) } },
            onDismiss: { withAnimation { advisorDismissed = true } },
            onEnableAI: { openAppleIntelligenceSettings() },
            currentTeamName: config.strategyIsAuto ? nil : model.strategyDisplayName(config.strategy))
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
    }

    /// A follow-up prompt's suggested assignee — the advisor's recommendation for THIS
    /// prompt, shown only when it differs from the chat's current team (so it's a genuine
    /// "maybe switch", not noise). nil while running, on the first message, or if dismissed.
    private var followupSuggestion: AdvisorEngine.Tier? {
        guard !vm.messages.isEmpty, !vm.isRunning, !suggestionDismissed,
              !advisorCardVisible, let tier = selectedTier else { return nil }
        let current = model.strategyDisplayName(config.strategy)
        let recommended = model.strategyDisplayName(tier.advice.strategy)
        guard recommended != current else { return nil }
        return tier
    }

    /// A quiet one-line chip: "For this, X might fit better — Switch". One tap swaps the
    /// The inline Advisor card shows only while composing the first message of
    /// a fresh chat — and it displaces the Token Saver banner (never stack two).
    private var advisorCardVisible: Bool {
        // Integrated identically in Chat AND Code — same full capabilities everywhere.
        vm.messages.isEmpty && !advisorDismissed && !inlineTiers.isEmpty
    }

    /// The currently-selected recommendation option.
    private var selectedTier: AdvisorEngine.Tier? {
        inlineTiers.first { $0.id == selectedTierID } ?? inlineTiers.first { $0.id == "balanced" } ?? inlineTiers.first
    }

    /// When the team is still "auto" and a recommendation is on screen, the activity
    /// panel previews the selected option's strategy so the right side shows what's
    /// recommended (not the placeholder default).
    private var advisorPreviewStrategy: Strategy? {
        // Preview whenever the recommendation card is up (Chat or Code) — not only for
        // "auto" chats — so the right panel tracks the selection everywhere.
        guard advisorCardVisible else { return nil }
        return selectedTier?.advice.strategy
    }

    /// The selected option's name (Economy / Recommended / Max), for the preview label.
    private var advisorPreviewLabel: String? {
        guard advisorPreviewStrategy != nil, let tier = selectedTier else { return nil }
        return model.t(tier.labelKey)
    }

    /// The one-line tradeoff note for the recommendation, for the selected-vs-recommended
    /// comparison in the activity panel.
    private var advisorPreviewReason: String? {
        guard advisorPreviewStrategy != nil, let tier = selectedTier else { return nil }
        return model.t(tier.noteKey)
    }

    /// Open System Settings so the user can turn on Apple Intelligence (for smarter,
    /// on-device recommendations). Tries the dedicated pane, then falls back.
    private func openAppleIntelligenceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preferences.AppleIntelligence",
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Hand this chat over to the Loop Builder, prefilled from an advice.
    private func createLoop(from advice: AdvisorEngine.Advice) {
        let plan = LoopPlan(name: config.name.isEmpty ? loopNameFromSource() : config.name,
                            kind: advice.loopKind,
                            goal: advice.goalSuggestion,
                            workerModel: advice.model,
                            sourceChatID: config.id,
                            sourceChatName: config.name.isEmpty ? loopNameFromSource() : config.name,
                            sourceIsCode: !(config.repoPath ?? "").isEmpty,
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
    /// Show "Run this as a loop?" once the user has sent a repeatable/goal-shaped message
    /// and no loop is already running over this chat — the contextual reveal for loops.
    private var loopSuggestionVisible: Bool {
        guard !vm.isRunning, !loopSuggestDismissed,
              !LoopStore.shared.isLoopRunning(forChat: config.id) else { return false }
        let firstAsk = vm.messages.first(where: { $0.role == .user })?.text ?? ""
        return !firstAsk.isEmpty && LoopSuggestion.looksRepeatable(firstAsk)
    }

    /// Whether any one-line suggestion wants the coach slot (so the saver tip yields to it).
    private var hasCoachSuggestion: Bool {
        followupSuggestion != nil || loopSuggestionVisible || repoSuggestionVisible
    }

    /// Exactly ONE neutral coach chip at a time: team-fit switch, else loop, else repo.
    /// Suggestions are calm and uniform — color is reserved for state, not offers.
    @ViewBuilder private var coachSlot: some View {
        if !advisorCardVisible {
            if let suggestion = followupSuggestion {
                CoachChip(icon: "wand.and.stars",
                          text: model.t("advisor.followup.suggest", model.strategyDisplayName(suggestion.advice.strategy)),
                          cta: model.t("advisor.followup.switch"),
                          action: {
                              model.applyTemplate(suggestion.advice.strategy, to: config.id)
                              withAnimation { suggestionDismissed = true }
                              model.flashSuccess(model.t("advisor.followup.switched", model.strategyDisplayName(suggestion.advice.strategy)))
                          },
                          onDismiss: { withAnimation { suggestionDismissed = true } })
            } else if loopSuggestionVisible {
                CoachChip(icon: "arrow.triangle.2.circlepath",
                          text: model.t("chat.loopSuggestion"), cta: model.t("chat.loopSuggestion.cta"),
                          action: { createLoopFromChat() },
                          onDismiss: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { loopSuggestDismissed = true } })
            } else if repoSuggestionVisible {
                CoachChip(icon: "folder.badge.plus",
                          text: model.t("chat.repoSuggestion"), cta: model.t("chat.repoSuggestion.cta"),
                          action: { model.pickRepo(for: config.id) },
                          onDismiss: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { repoSuggestDismissed = true } })
            }
        }
    }

    /// A connected provider that ISN'T this chat's provider — the one to ask for a second
    /// opinion. nil when only one provider is connected.
    private var secondOpinionProvider: AIProvider? {
        model.connectedProviders.sorted { $0.rawValue < $1.rawValue }.first { $0 != config.provider }
    }

    /// Run the last ask on another provider and append its answer, labeled.
    private func runSecondOpinion(from provider: AIProvider) async {
        let modelID = provider.models.first?.id ?? ""
        let cwd = model.repoURL(for: config)?.path
        let header = model.t("chat.secondOpinion.header", provider.displayName) + "\n\n"
        await vm.secondOpinion(provider: provider, model: modelID, cwd: cwd,
                               runner: model.oneShotRunner(readOnly: true), headerPrefix: header)
    }

    /// Offer to attach a folder when the user talks about code but no repo is bound —
    /// the agents can only read/edit code once there's a folder (Code mode).
    private var repoSuggestionVisible: Bool {
        guard !vm.isRunning, !repoSuggestDismissed,
              (config.repoPath ?? "").isEmpty else { return false }
        let firstAsk = vm.messages.first(where: { $0.role == .user })?.text ?? ""
        return !firstAsk.isEmpty && RepoMention.mentionsCode(firstAsk)
    }

    private func createLoopFromChat() {
        let source = vm.messages.first(where: { $0.role == .user })?.text
            ?? (vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vm.input)
        if let source {
            createLoop(from: AdvisorEngine.advise(task: source))
        } else {
            let plan = LoopPlan(name: config.name,
                                sourceChatID: config.id,
                                sourceChatName: config.name,
                                sourceIsCode: !(config.repoPath ?? "").isEmpty,
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
                    .lineLimit(1)
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
                            // Until the first message picks a team, show "Auto team"
                            // (a wand), not a concrete strategy that looks pre-decided.
                            if config.strategyIsAuto {
                                Image(systemName: "wand.and.stars")
                                    .scaledFont(9, weight: .semibold).foregroundStyle(Theme.accent)
                                Text(model.t("chat.autoTeam.badge"))
                                    .font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
                            } else {
                                Text(model.strategyDisplayName(config.strategy))
                                    .font(.sfCaption2.weight(.medium))
                                    .foregroundStyle(Theme.accent)
                            }
                            // Explicit disclosure cue: the capsule is a menu, not a label.
                            Image(systemName: "chevron.down")
                                .scaledFont(9, weight: .semibold)
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
                        // No repo yet → a one-tap "connect a folder" right in the chat,
                        // so code work is reachable without hunting for it.
                        Button { _ = model.pickRepo(for: config.id) } label: {
                            Label(model.t("chat.connectRepo"), systemImage: "folder.badge.plus")
                                .font(.sfCaption2)
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)   // CTA → coral (the one accent)
                        .help(model.t("chat.connectRepo.help"))
                    }
                }
            }
            .layoutPriority(0)
            Spacer(minLength: Space.s)
            // The trailing controls are a fixed cluster: they never get squeezed when
            // the chat column narrows (e.g. viewing an agent) — the title truncates.
            HStack(spacing: Space.s) {
            // Persistent full-access indicator — visible and one-tap revocable, so
            // "allow always" is never a silent, irreversible state.
            if vm.elevatedPermissions {
                Button { vm.disableElevation() } label: {
                    Label(model.t("chat.fullAccessOn"), systemImage: "checkmark.shield.fill")
                        .font(.sfCaption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warning.opacity(0.18)))
                        .foregroundStyle(Theme.warningText)
                }
                .buttonStyle(.plain)
                .help(model.t("chat.fullAccessOn.help"))
            }
            // Context weight: the token count colored by how heavy every further
            // re-read of this conversation has become (Token Saver).
            HStack(spacing: 6) {
                ContextWeightPill(tokens: vm.totalTokens)
                if vm.totalCostUSD > 0 {
                    Text(String(format: "\(vm.costEstimated ? "~" : "")$%.2f", vm.totalCostUSD))
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                        .help(vm.costEstimated ? model.t("usage.estimated.help") : "")
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
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, Space.m).padding(.bottom, Space.m).padding(.top, model.titlebarTopInset)
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

    /// Code mode is offered only when the chat targets a real folder on disk AND the
    /// provider streams the file/command events the workspace renders (Claude today).
    private var codeModeEligible: Bool {
        !(config.repoPath ?? "").isEmpty && config.provider.supportsCodeMode
    }

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

    /// The completion beat: a subtle centered capsule that closes a finished turn with
    /// its own elapsed / tokens / cost, so a reply no longer just ends in silence.
    @ViewBuilder
    private var completionBeat: some View {
        if !vm.isRunning, vm.messages.last?.role == .assistant, let turn = vm.history.last {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.success)
                Text(completionSummary(turn))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.m).padding(.vertical, 5)
            .background(Capsule().fill(Theme.hairline.opacity(0.5)))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Space.s)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
        }
    }

    /// "Completed · 1m 04s · 12.3k · $0.04" — only the parts that have a value.
    private func completionSummary(_ turn: TurnActivity) -> String {
        var parts = [model.t("activity.done.turn"),
                     activityElapsed(from: turn.startedAt, to: turn.endedAt)]
        if turn.tokensUsed > 0 {
            parts.append(turn.tokensUsed >= 1000
                         ? String(format: "%.1fk", Double(turn.tokensUsed) / 1000)
                         : "\(turn.tokensUsed)")
        }
        if turn.costUSD > 0 { parts.append(String(format: "$%.2f", turn.costUSD)) }
        return parts.joined(separator: " · ")
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.messageSpacing) {
                    if vm.messages.isEmpty { emptyState }
                    ForEach(vm.messages) { message in
                        // While a turn is starting, the assistant message is still
                        // empty — the activityRow below is the single "working"
                        // indicator, so don't also render an empty bubble with its
                        // own spinner (that was the redundant top sphere).
                        let streaming = vm.isRunning && message.role == .assistant
                            && message.id == vm.messages.last?.id
                        if !(streaming && message.text.isEmpty) {
                        bubble(message, isStreaming: streaming)
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
                    }
                    if vm.isRunning {
                        activityRow.id("activity")
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    // A quiet close on a finished turn: "Completed · 1m 04s · 12.3k · $0.04"
                    // (per-turn stats — the header shows the running cumulative total).
                    completionBeat
                }
                .padding(Space.l)
                // ChatGPT-calm: a centered reading column with generous gutters, instead
                // of hugging the left edge.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: vm.messages.count)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: vm.isRunning)
            }
            .onChange(of: vm.messages.last?.text) { scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            // Open a chat at its LAST message, not the top.
            .onAppear {
                if let last = vm.messages.last?.id {
                    DispatchQueue.main.async { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            // No aurora/gradient behind the chat: the conversation sits on the app's one
            // uniform translucent surface, so the chat matches every other panel.
        }
    }

    /// Artifact scans are memoized by message text (same pattern as MarkdownView's
    /// block cache): `vm.messages` mutates on every streamed delta, so every visible
    /// finished bubble re-renders per chunk — without this, each of those renders
    /// re-line-splits the whole message just to decide whether to show the button.
    private static let artifactCache = NSCache<NSString, ArtifactBox>()
    private final class ArtifactBox { let artifacts: [Artifact]; init(_ a: [Artifact]) { artifacts = a } }

    private func cachedArtifacts(for text: String) -> [Artifact] {
        let key = text as NSString
        if let hit = Self.artifactCache.object(forKey: key) { return hit.artifacts }
        let extracted = Artifact.extract(from: text)
        Self.artifactCache.countLimit = 400
        Self.artifactCache.setObject(ArtifactBox(extracted), forKey: key)
        return extracted
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, isStreaming: Bool) -> some View {
        if message.role == .user {
            // User: compact bubble on the right. Capped at ~560 so a long message shares
            // the same calm column as the assistant (not a full-width coral slab), with a
            // near-flat shadow so the transcript doesn't read as a row of buttons (wave B).
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.sfBodyM)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .foregroundStyle(Theme.onAccent)
                    .shadow(color: Theme.coralTextShadow, radius: 0.5, x: 0, y: 0.5)   // legible on bright coral
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .frame(maxWidth: 560, alignment: .trailing)
                    // The user's turn: a flat coral pill — signature coral kept, but the glow
                    // and gradient dropped for ChatGPT-calm (brand decision 2026-07-24).
                    .background(RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous).fill(Theme.coral))
                    .contextMenu {
                        copyButton(message.text)
                        Button { editMessage(message) } label: {
                            Label(model.t("chat.edit"), systemImage: "pencil")
                        }.disabled(vm.isRunning)
                    }
            }
        } else {
            // Assistant: a soft rounded bubble (reference-style), with an avatar.
            HStack(alignment: .top, spacing: Space.s) {
                Group {
                    if isStreaming {
                        WorkingLogo(size: 20)
                    } else {
                        // A finished bubble's globe holds still — no 30fps Canvas per
                        // message for the whole transcript's lifetime.
                        CoralSphere(size: 28, animating: false)
                    }
                }
                .frame(width: 28, height: 28)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    // No bubble for the assistant — it writes directly on the ambient
                    // background (only the user's messages are boxed). While streaming
                    // we render PLAIN text (re-parsing Markdown on every token is what
                    // made it feel choppy); the full Markdown renders once it settles.
                    Group {
                        if isStreaming {
                            Text(message.text)
                                .font(.sfBodyM).lineSpacing(Theme.bodyLineSpacing)
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                        } else {
                            MarkdownView(text: message.text)
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contextMenu {
                            copyButton(message.text)
                            Button { regenerate(message) } label: {
                                Label(model.t("chat.regenerate"), systemImage: "arrow.clockwise")
                            }.disabled(vm.isRunning)
                        }
                    if !message.text.isEmpty {
                        let copied = copiedMessageID == message.id
                        HStack(spacing: Space.m) {
                            Button { copy(message) } label: {
                                Label(copied ? model.t("chat.copied") : model.t("chat.copy"),
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .labelStyle(.iconOnly).font(.sfCaption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isStreaming ? AnyShapeStyle(.quaternary)
                                             : (copied ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary)))
                            .disabled(isStreaming)
                            .help(model.t("chat.copy"))
                            // Substantial code / HTML / SVG blocks open in a focused
                            // artifact viewer instead of scrolling inline.
                            if !isStreaming {
                                let arts = cachedArtifacts(for: message.text)
                                if !arts.isEmpty {
                                    Button { shownArtifacts = arts; showArtifacts = true } label: {
                                        Label(model.t("artifact.open"), systemImage: "rectangle.on.rectangle.angled")
                                            .font(.sfCaption2)
                                    }
                                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                                }
                            }
                            Spacer(minLength: 0)
                            // The differentiator, made glanceable: a "team of N ▸" chip on the
                            // latest answer when a real team produced it. One tap opens the
                            // activity panel (the roster + what each agent did). Keeps the power
                            // visible even when the machinery is collapsed.
                            if !isStreaming, message.id == vm.messages.last?.id {
                                let teamSize = config.strategy.subagentRoles.count
                                if teamSize > 0 {
                                    Button { showActivity = true } label: {
                                        Label(model.t("chat.answeredByTeam", teamSize + 1), systemImage: "person.3.sequence.fill")
                                            .font(.sfCaption2.weight(.medium))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)   // finished-turn attribution, not live → neutral (teal = live only)
                                    .help(model.t("chat.answeredByTeam.help"))
                                }
                                // Cross-provider, made tangible: a "second opinion from X ▸"
                                // on the latest answer when another provider CLI is connected.
                                if let other = secondOpinionProvider {
                                    if vm.isSecondOpinionRunning {
                                        WorkingLogo(size: 12)
                                    } else {
                                        Button { Task { await runSecondOpinion(from: other) } } label: {
                                            Label(model.t("chat.secondOpinion", other.displayName), systemImage: "arrow.triangle.branch")
                                                .font(.sfCaption2.weight(.medium))
                                        }
                                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                                        .help(model.t("chat.secondOpinion.help", other.displayName))
                                    }
                                }
                            }
                        }
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
        VStack(spacing: Space.l) {
            // Airy, centered greeting (reference): a large iridescent presence orb,
            // a casual time-of-day greeting, the welcome copy under it, then the team
            // hook and glass suggestion pills.
            CoralSphere(size: 88)
                .restingShadow(diameter: 88)   // the hero object rests on the reef
                .staggeredAppear(index: 0)
            // Hero greeting + a single coral accent-dot (the reference's signature gesture).
            (Text(chatGreeting).foregroundStyle(Theme.ink)
                + Text(".").foregroundStyle(Theme.coral))
                .font(.sfHero)
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
                .staggeredAppear(index: 1)
            Text(model.t("chat.empty"))
                .font(.sfCardTitle)
                .foregroundStyle(Theme.secondaryOnMaterial)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
                .staggeredAppear(index: 2)
            strategyHook
                .staggeredAppear(index: 3)
            VStack(spacing: Space.s) {
                ForEach(Array(["chat.suggest1", "chat.suggest2", "chat.suggest3"].enumerated()),
                        id: \.element) { index, key in
                    Button { vm.input = model.t(key) } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: "arrow.up.forward.square").foregroundStyle(Theme.accent)
                            Text(model.t(key)).font(.sfCallout).foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Tidy, high-contrast pills: a clean neutral card fill under a
                        // hairline (readability over glass) — the label stays crisp ink
                        // instead of a washed material tint.
                        .background(
                            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                                .fill(Theme.cardBg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                    .staggeredAppear(index: index + 4)
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// A casual, time-of-day-aware greeting for this empty chat. Seeded by the chat's
    /// id so each new chat gets its own line (stable — it won't reshuffle on redraw),
    /// and personalized with the signed-in user's first name when we have it.
    private var chatGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let first = auth.account?.displayName?
            .split(separator: " ").first.map(String.init)
        // Deterministic FNV-ish hash of the chat's UUID so the pick is stable per chat.
        let seed = config.id.uuidString.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return DaypartGreeting.line(langCode: model.langCode, hour: hour, seed: seed, name: first)
    }

    /// The differentiator, front and center on an empty chat: this chat is driven
    /// by the team you designed — show it (diagram + name + size + what it's for).
    /// When the team is still "auto", we instead invite the user to just describe
    /// their task (we'll pick the agents) — so nothing looks pre-decided.
    @ViewBuilder
    private var strategyHook: some View {
        if config.strategyIsAuto {
            autoTeamHook
        } else {
            chosenTeamHook
        }
    }

    private var autoTeamHook: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26)).foregroundStyle(Theme.accent)
                .frame(width: 104, height: 64)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
                .breathingGlow(color: Theme.coral, enabled: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("chat.autoTeam.badge"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Text(model.t("chat.autoTeam.title")).font(.sfCardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.t("chat.autoTeam.desc"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: 560, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.innerCorner))
    }

    private var chosenTeamHook: some View {
        let teammates = config.strategy.subagentRoles.reduce(0) { $0 + max(1, $1.count) }
        return HStack(spacing: Space.m) {
            StrategyThumbnail(strategy: config.strategy)
                .frame(width: 104, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                // A subtle coral breath on the team diagram — the hero of the empty
                // state — quiet enough to invite, stilled under Reduce Motion.
                .breathingGlow(color: Theme.coral, enabled: false)
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
                    Image(systemName: "arrow.turn.down.right").scaledFont(9)
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
                    ForEach(Array(vm.editedFiles.reversed()), id: \.self) { path in fileChip(path) }
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
            .buttonStyle(.plain).foregroundStyle(.secondary)   // minor repeated action → neutral
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
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.warningText).font(.system(size: 12))
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

    /// Whether an error message is an authentication failure (so we offer reconnect).
    private func isAuthError(_ error: String) -> Bool {
        let e = error.lowercased()
        return e.contains("401") || e.contains("authenticate") || e.contains("credentials")
            || e.contains("sign in") || e.contains("log in") || e.contains("unauthorized")
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.sfCaption2).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The failure is actionable: open Connected Services (the usual fix for a
            // provider run), export the log, or copy the message.
            HStack(spacing: Space.s) {
                // Auth failures self-heal: sign in again (browser), then auto-retry the
                // same turn — the user never has to leave for Terminal or re-type.
                if isAuthError(error) {
                    Button { reconnecting = true } label: {
                        Label(model.t("chat.reconnectRetry"), systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(.moon).controlSize(.small)
                } else {
                    Button(model.t("banner.fix")) { model.navSection = .services }
                        .controlSize(.small)
                }
                Button(model.t("banner.exportLog")) { model.exportDiagnostics() }
                    .controlSize(.small)
                CopyButton(text: error, help: model.t("chat.copy"))
                Spacer()
                Button { vm.errorText = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.10))
        // Reconnect flow (install if needed → web sign-in) then auto-retry the turn.
        .sheet(isPresented: $reconnecting) {
            ProviderConnectSheet(provider: config.provider) {
                vm.errorText = nil
                vm.retryAllowingAll()
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if branchStat != nil {
                branchBar.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !slashMatches.isEmpty {
                slashPopover.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !mentionMatches.isEmpty {
                mentionPopover.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !vm.queued.isEmpty { queuedChips }
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
                // High-contrast input: crisp ink glyphs and a coral caret so the
                // composer reads clearly over the frosted bar (never washed).
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .focused($inputFocused)
                // @-mentions + /-commands: refresh both palettes as the draft changes.
                .onChange(of: vm.input) { refreshMentions(); refreshSlash() }
                .onSubmit { send() }
                // Up arrow on an empty field recalls the last message to edit/resend.
                .onKeyPress(.upArrow) {
                    guard vm.input.isEmpty,
                          let last = vm.messages.last(where: { $0.role == .user }) else { return .ignored }
                    vm.input = last.text
                    return .handled
                }

            if vm.isRunning {
                // Typing while it works? Enter (or this button) queues the message — it
                // sends automatically when the current turn finishes. Stop stays available.
                if vm.hasComposerContent {
                    circularSendButton(system: "arrow.up", accessibility: model.t("chat.queue"),
                                       enabled: !engineMissing) { send() }
                }
                circularSendButton(system: "stop.fill", accessibility: model.t("chat.stop"),
                                   enabled: true) { vm.stop() }
            } else {
                circularSendButton(system: "arrow.up", accessibility: model.t("chat.send"),
                                   enabled: vm.canSend && !engineMissing) { send() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            }
            // A single SOLID rounded field wraps the whole composer row (reference
            // "Ask anything…" input). De-glassed (design review, wave A): a crisp opaque
            // cardBg + hairline + focus ring reads more premium than a washed glass over
            // the most important control in the app — and it's cheaper.
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.cardBg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(inputFocused ? Theme.focusRing : Theme.hairline, lineWidth: inputFocused ? 1.5 : 1)
            )
            .shadow(color: inputFocused ? Theme.focusGlow : .clear, radius: 8)
            .animation(.easeOut(duration: 0.18), value: inputFocused)
            composerFooter
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: mentionMatches.count)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: slashMatches.count)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: branchStat)
        .padding(Space.m)
        .background(.bar)
        .sensoryFeedback(.impact(weight: .medium), trigger: sendPulse)
        // Load the repo's file list once (and when the repo changes) for @-mentions.
        .task(id: config.repoPath) { await loadRepoFiles() }
        // Branch/PR context bar: load on repo change, refresh when a turn finishes
        // (edits/commits may have moved the branch or its diff).
        .task(id: config.repoPath) { await refreshBranch() }
        .onChange(of: vm.isRunning) { _, running in
            if !running { Task { await refreshBranch() } }
        }
        .sheet(isPresented: $showArtifacts) {
            ArtifactSheet(artifacts: shownArtifacts).environment(model)
        }
        // Live per-tool permission gate ("Ask" mode) — the run waits on the answer.
        .sheet(isPresented: Binding(get: { vm.pendingPermission != nil },
                                    set: { if !$0 { vm.pendingPermission = nil } })) {
            if let p = vm.pendingPermission { permissionSheet(p) }
        }
    }

    /// The reference's circular gradient send control: a coral-filled Circle with a
    /// white glyph and a soft coral shadow. Doubles as the stop button while running
    /// (same shape, `stop.fill` glyph) — the action and enabled state are passed in.
    private func circularSendButton(system: String, accessibility: String,
                                    enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .shadow(color: Theme.coralTextShadow, radius: 0.5, x: 0, y: 0.5)   // legible on bright coral
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.primaryFill))
                .shadow(color: Theme.accentGlow, radius: 6, x: 0, y: 2)
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(accessibility)
        .accessibilityLabel(accessibility)
    }

    private func permissionSheet(_ p: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.accent)
                Text(model.t("perm.title", p.toolName)).font(.sfCardTitle)
            }
            if !p.detail.isEmpty {
                ScrollView {
                    Text(p.detail).font(.sfCode).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
            }
            HStack(spacing: Space.s) {
                Button(role: .destructive) { vm.respondPermission(p.id, allow: false) } label: {
                    Text(model.t("perm.deny")).frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                Button { vm.respondPermission(p.id, allow: true) } label: {
                    Text(model.t("perm.once")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.moon).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            Button { vm.respondPermission(p.id, allow: true, always: true) } label: {
                Label(model.t("perm.always"), systemImage: "checkmark.shield")
                    .font(.sfCaption2)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(Space.l)
        .frame(width: 460)
    }

    // MARK: - @-mention autocomplete

    /// A popover of repo files matching the `@token` currently being typed. Selecting
    /// one inserts its path so the model knows which file to read (it's under cwd).
    private var mentionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(mentionMatches, id: \.self) { path in
                Button { insertMention(path) } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Theme.accent)
                        Text(path).font(.sfCaption2).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverTint(cornerRadius: 6)
            }
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// The active `@token` in the draft — the run after the last `@` when that `@`
    /// begins a word and nothing after it is whitespace. Nil when not mentioning.
    private func currentMentionToken(_ s: String) -> String? {
        guard let at = s.range(of: "@", options: .backwards) else { return nil }
        if at.lowerBound != s.startIndex {
            let before = s[s.index(before: at.lowerBound)]
            if !before.isWhitespace { return nil }
        }
        let after = s[at.upperBound...]
        if after.contains(where: { $0.isWhitespace }) { return nil }
        return String(after)
    }

    private func refreshMentions() {
        guard let token = currentMentionToken(vm.input), !allRepoFiles.isEmpty else {
            if !mentionMatches.isEmpty { mentionMatches = [] }
            return
        }
        let q = token.lowercased()
        let hits = q.isEmpty ? allRepoFiles : allRepoFiles.filter { $0.lowercased().contains(q) }
        // Shorter paths (closer to the repo root) first; basename-prefix hits win.
        mentionMatches = Array(hits.sorted {
            let ap = ($0 as NSString).lastPathComponent.lowercased().hasPrefix(q)
            let bp = ($1 as NSString).lastPathComponent.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return $0.count < $1.count
        }.prefix(8))
    }

    private func insertMention(_ path: String) {
        guard let at = vm.input.range(of: "@", options: .backwards) else { return }
        vm.input.replaceSubrange(at.lowerBound..., with: "@\(path) ")
        mentionMatches = []
    }

    /// Enumerate the repo's files (relative paths), skipping heavy/hidden dirs, so
    /// @-mention autocomplete has something to match. Runs off the main actor.
    private func loadRepoFiles() async {
        guard let repo = config.repoPath, !repo.isEmpty else { allRepoFiles = []; return }
        let files = await Task.detached(priority: .utility) { () -> [String] in
            let root = URL(fileURLWithPath: repo)
            let skip: Set<String> = [".git", "node_modules", ".build", "DerivedData",
                                     ".next", "dist", "build", ".venv", "Pods", ".swiftpm"]
            var out: [String] = []
            let en = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            let prefix = root.path + "/"
            while let u = en?.nextObject() as? URL {
                if skip.contains(u.lastPathComponent) { en?.skipDescendants(); continue }
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { continue }
                out.append(u.path.replacingOccurrences(of: prefix, with: ""))
                if out.count >= 4000 { break }
            }
            return out
        }.value
        allRepoFiles = files
    }

    // MARK: - Slash commands

    private struct SlashCommand: Identifiable {
        enum Action { case mode(String), effort(Effort), clear }
        let name: String
        let descKey: String
        let icon: String
        let action: Action
        var id: String { name }
    }

    /// Built-in composer commands (Claude-style `/`): switch mode, set effort, clear.
    private var slashCommands: [SlashCommand] {
        [.init(name: "accept", descKey: "slash.accept", icon: "pencil.circle", action: .mode("acceptEdits")),
         .init(name: "plan", descKey: "slash.plan", icon: "list.bullet.clipboard", action: .mode("plan")),
         .init(name: "auto", descKey: "slash.auto", icon: "bolt.circle", action: .mode("bypassPermissions")),
         .init(name: "fast", descKey: "slash.fast", icon: "hare", action: .effort(.fast)),
         .init(name: "think", descKey: "slash.think", icon: "brain", action: .effort(.high)),
         .init(name: "ultra", descKey: "slash.ultra", icon: "sparkles", action: .effort(.ultra)),
         .init(name: "clear", descKey: "slash.clear", icon: "eraser", action: .clear)]
    }

    private var slashPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(slashMatches) { cmd in
                Button { runSlash(cmd) } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: cmd.icon).font(.system(size: 11)).foregroundStyle(Theme.accent)
                            .frame(width: 16)
                        Text("/\(cmd.name)").font(.sfCaption2.weight(.semibold)).monospaced()
                        Text(model.t(cmd.descKey)).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverTint(cornerRadius: 6)
            }
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// The palette shows while the draft is a lone `/token` (no space yet).
    private func refreshSlash() {
        let s = vm.input
        guard s.first == "/", !s.contains(" ") else {
            if !slashMatches.isEmpty { slashMatches = [] }
            return
        }
        let q = s.dropFirst().lowercased()
        slashMatches = slashCommands.filter { q.isEmpty || $0.name.hasPrefix(q) }
    }

    private func runSlash(_ cmd: SlashCommand) {
        switch cmd.action {
        case .mode(let m): withAnimation(.easeOut(duration: 0.15)) { vm.permissionMode = m }
        case .effort(let e): vm.effort = e
        case .clear:
            vm.clearTranscript()
            saveDraft("")
        }
        vm.input = ""
        slashMatches = []
    }

    // MARK: - Working-branch context bar

    /// The branch being worked on, its ±line diff vs the default branch, and any PR
    /// with its state — mirrors Claude's branch/PR bar above the composer.
    @ViewBuilder
    private var branchBar: some View {
        if let stat = branchStat {
            HStack(spacing: Space.s) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(Theme.accent)
                if let pr = prInfo {
                    Text("#\(pr.number)").font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Text(CodeGit.repoName(from: config.repoPath ?? ""))
                    .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                Text(stat.branch)
                    .font(.sfCaption2.weight(.medium)).lineLimit(1).truncationMode(.middle)
                if stat.insertions > 0 || stat.deletions > 0 {
                    HStack(spacing: 5) {
                        Text("+\(stat.insertions)").foregroundStyle(Theme.success)
                        Text("−\(stat.deletions)").foregroundStyle(Theme.danger)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                Spacer(minLength: 0)
                if let pr = prInfo { prStateBadge(pr) }
            }
            .padding(.horizontal, Space.m).padding(.vertical, 6)
            .glassPanel(cornerRadius: Theme.innerCorner)
            .contentShape(Rectangle())
            .onTapGesture {
                if let pr = prInfo, let u = URL(string: pr.url) { NSWorkspace.shared.open(u) }
            }
            .help(prInfo?.title ?? stat.branch)
        }
    }

    private func prStateBadge(_ pr: GitHubCLI.PRInfo) -> some View {
        let (labelKey, color): (String, Color) = {
            if pr.isDraft { return ("pr.state.draft", Theme.inkDim) }
            switch pr.state.uppercased() {
            case "MERGED": return ("pr.state.merged", Color(red: 0.55, green: 0.36, blue: 0.96))
            case "CLOSED": return ("pr.state.closed", Theme.danger)
            default: return ("pr.state.open", Theme.success)
            }
        }()
        return Text(model.t(labelKey))
            .font(.sfCaption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    /// Refresh the branch stat + PR status off-main (cheap git/gh calls).
    private func refreshBranch() async {
        guard let repo = config.repoPath, !repo.isEmpty else { branchStat = nil; prInfo = nil; return }
        let stat = await CodeGit.branchStat(repo: repo)
        branchStat = stat
        if let branch = stat?.branch, !(stat?.isOnBase ?? true) {
            prInfo = await GitHubCLI.prInfo(repo: repo, branch: branch)
        } else {
            prInfo = nil
        }
    }

    // MARK: - Composer footer (permission mode + model · effort)

    private struct ModeOption { let raw: String; let labelKey: String; let icon: String; let key: Character }
    private var modeOptions: [ModeOption] {
        [.init(raw: "ask", labelKey: "mode.ask", icon: "hand.raised", key: "1"),
         .init(raw: "acceptEdits", labelKey: "mode.acceptEdits", icon: "pencil.circle", key: "2"),
         .init(raw: "plan", labelKey: "mode.plan", icon: "list.bullet.clipboard", key: "3"),
         .init(raw: "bypassPermissions", labelKey: "mode.auto", icon: "bolt.circle", key: "4")]
    }
    private var currentMode: ModeOption { modeOptions.first { $0.raw == vm.permissionMode } ?? modeOptions[0] }

    private var composerFooter: some View {
        // On a brand-new chat (no messages yet), keep the box clean: just a subtle "…" to
        // reveal the controls. Sensible defaults (auto team, default effort/mode) apply.
        Group {
            if !vm.messages.isEmpty || showComposerControls {
                HStack(spacing: Space.s) {
                    modeMenu
                    Spacer(minLength: Space.s)
                    ContextWindowChip(breakdown: ContextBreakdown.estimate(
                        transcript: vm.messages, strategy: config.strategy))
                    modelEffortChip
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { showComposerControls = true } } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .help(model.t("composer.options"))
                    .accessibilityLabel(model.t("composer.options"))
                }
            }
        }
        .padding(.horizontal, 2)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: vm.effort)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: vm.permissionMode)
    }

    /// Aceptar ediciones / Plan / Automático — the CLI permission mode, switchable
    /// per chat (like Claude Code's mode cycle), with 1·2·3 shortcuts.
    private var modeMenu: some View {
        Menu {
            ForEach(modeOptions, id: \.raw) { opt in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { vm.permissionMode = opt.raw }
                } label: {
                    Label(model.t(opt.labelKey),
                          systemImage: vm.permissionMode == opt.raw ? "checkmark" : opt.icon)
                }
                .keyboardShortcut(KeyEquivalent(opt.key), modifiers: [])
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentMode.icon).font(.system(size: 10))
                Text(model.t(currentMode.labelKey)).font(.sfCaption2.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").scaledFont(7).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(model.t("mode.help"))
    }

    private var modelDisplayName: String { ClaudeModel(rawValue: vm.model)?.displayName ?? "Claude" }

    /// "Opus 4.8 · Alto" — tapping opens the effort slider (Faster ↔ Smarter).
    private var modelEffortChip: some View {
        Button { showEffort = true } label: {
            HStack(spacing: 6) {
                Text(modelDisplayName).font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                Text(model.t(vm.effort.labelKey))
                    .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentSoft))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEffort, arrowEdge: .bottom) { effortPopover }
        .help(model.t("effort.help"))
    }

    private var effortPopover: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                Text(model.t("effort.title")).font(.sfCardTitle)
                Text(model.t(vm.effort.labelKey)).font(.sfCallout).foregroundStyle(Theme.accent)
                Spacer()
                // The "smartest" end gets the app's living dot-grid flourish.
                if vm.effort == .ultra && !reduceMotion { WaveDotGrid(size: 26, color: Theme.accent) }
            }
            HStack {
                Text(model.t("effort.faster")).font(.sfCaption2).foregroundStyle(.secondary)
                Spacer()
                Text(model.t("effort.smarter")).font(.sfCaption2).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { vm.effort.sliderValue },
                                  set: { vm.effort = Effort.at($0) }), in: 0...3, step: 1)
                .tint(Theme.accent)
            Text(model.t(vm.effort.blurbKey)).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(width: 288)
    }

    /// Queued messages waiting behind the running turn — each removable before it fires.
    private var queuedChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").scaledFont(9)
                Text(model.t("chat.queued.count", vm.queued.count)).font(.sfCaption2)
            }
            .foregroundStyle(Theme.accent)
            ForEach(vm.queued) { q in
                HStack(spacing: 6) {
                    Text(q.text.isEmpty ? model.t("chat.queued.attachmentsOnly") : q.text)
                        .font(.sfCaption2).lineLimit(1).foregroundStyle(Theme.ink)
                    if !q.attachments.isEmpty {
                        Image(systemName: "paperclip").scaledFont(8).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button { vm.removeQueued(q.id) } label: {
                        Image(systemName: "xmark").scaledFont(8)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
            }
        }
    }

    /// Chips for staged attachments, each removable.
    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(vm.attachments) { att in
                    HStack(spacing: 4) {
                        Image(systemName: "doc").scaledFont(9)
                        Text(att.name).font(.sfCaption2).lineLimit(1)
                        Button { vm.attachments.removeAll { $0.id == att.id } } label: {
                            Image(systemName: "xmark").scaledFont(8)
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

    /// Edit a user message: rewind the conversation to before it, drop it, and load
    /// its text back into the composer to change and resend (a fresh session).
    private func editMessage(_ message: ChatMessage) {
        guard !vm.isRunning, let idx = vm.messages.firstIndex(where: { $0.id == message.id }) else { return }
        let text = message.text
        vm.truncate(from: idx)
        vm.input = text
        inputFocused = true
    }

    /// Regenerate an assistant reply: rewind to the user turn that produced it and
    /// re-run that same prompt (fresh session), so a different answer can come out.
    private func regenerate(_ message: ChatMessage) {
        guard !vm.isRunning, let idx = vm.messages.firstIndex(where: { $0.id == message.id }) else { return }
        // The user prompt is the message just before this assistant reply.
        let userIdx = idx - 1
        guard vm.messages.indices.contains(userIdx), vm.messages[userIdx].role == .user else { return }
        let prompt = vm.messages[userIdx].text
        vm.truncate(from: userIdx)
        vm.input = prompt
        send()
    }

    private func send() {
        guard vm.hasComposerContent, !engineMissing else { return }
        sendPulse += 1          // tactile confirmation the message left (or queued)
        vm.submit()             // sends now, or queues behind the running turn
        saveDraft("")           // sent → clear the persisted draft
        inputFocused = true     // keep the composer focused for the next turn
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: (any Hashable)? = vm.isRunning ? "activity" : vm.messages.last?.id
        guard let target else { return }
        // Animating the scroll on every streamed token stutters — follow instantly
        // while streaming, animate only when a turn settles.
        if reduceMotion || vm.isRunning {
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

/// One calm, uniform "coach" suggestion chip — the single shape every contextual offer
/// (team-fit switch, run-as-loop, attach-a-folder) shares. Neutral card + hairline, one
/// muted accent glyph, a borderless CTA, a tertiary dismiss. Color is reserved for STATE
/// strips (errors, blocked permissions), never for suggestions (design review, wave B).
private struct CoachChip: View {
    let icon: String
    let text: String
    let cta: String
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.accent)
            Text(text).font(.sfCaption2).foregroundStyle(Theme.ink).lineLimit(2)
            Spacer(minLength: Space.s)
            Button(cta, action: action)
                .buttonStyle(.borderless).controlSize(.small).font(.sfCaption2.weight(.semibold))
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, Space.m).padding(.bottom, Space.xs)
    }
}

#Preview("Chat") { ChatPreviewHost() }
#Preview("Chat (Dark)") { ChatPreviewHost().preferredColorScheme(.dark) }
