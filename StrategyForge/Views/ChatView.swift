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
    /// The specific provider being reconnected from the mid-run "needs re-login" banner
    /// (may be a worker's provider, e.g. Gemini — not necessarily the chat's own).
    @State private var reconnectingProvider: AIProvider?
    /// Confirmation before merging an IRREVERSIBLE isolated change (migrations, deletions, prod,
    /// money) — the blast-radius gate: this lane never merges silently.
    @State private var confirmIrreversibleMerge = false
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
    /// Isolation ("Aislar") review-diff sheet.
    @State private var showIsolationDiff = false
    @State private var isolationDiffText = ""
    /// "Ship" (Bet 4): detected deploy CLIs + a confirmed deploy + its result.
    @State private var shipTools: [ShipTool] = []
    @State private var shipTool: ShipTool?
    @State private var showShipConfirm = false
    @State private var showShipResult = false
    @State private var shipping = false
    @State private var shipResult: ShipResult?
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
        // ONE right-side slot, owned by either Code Mode OR the activity panel (mutually
        // exclusive) — both are INLINE columns that push the conversation, never overlay it.
        // The conversation is never occluded; opening a panel reflows it. Header toggles
        // (list on the left, activity on the right) are the single place to show/hide.
        HStack(spacing: 0) {
            chatColumn
            if codeMode {
                ResizableDivider(
                    width: Binding(get: { CGFloat(codeW) }, set: { codeW = Double($0) }),
                    range: 380...900, sign: -1)
                CodeModeView(vm: vm)
                    .frame(width: CGFloat(codeW))
            } else if showActivity {
                ResizableDivider(
                    width: Binding(get: { CGFloat(activityW) }, set: { activityW = Double($0) }),
                    range: 300...560, sign: -1)
                activityColumn
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

    /// The activity panel as an INLINE right column that pushes the conversation (never
    /// overlays it) — a sibling of the chat list and Code Mode, on the same translucent
    /// column surface. Its width is the `ResizableDivider`-driven `activityW`.
    private var activityColumn: some View {
        Group {
            if let focus = agentFocus {
                // Drilling into one agent REPLACES the roster within the same column (a back
                // button pops), so we never stack a third rightward column at narrow widths.
                SubagentDetailPanel(vm: vm, focus: focus) { agentFocus = nil }
            } else {
                AgentActivityPanel(vm: vm, focus: $agentFocus,
                                   previewStrategy: advisorPreviewStrategy, previewLabel: advisorPreviewLabel,
                                   previewReason: advisorPreviewReason)
            }
        }
        .frame(width: CGFloat(activityW))
        // A whisper-thin hairline seam (not a hard Divider) so the panel reads as part of
        // the same surface as the conversation, not a bolted-on column.
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline.opacity(0.5)).frame(width: 1)
        }
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
        }
        // The composer + its banners are pinned to the BOTTOM as a safe-area inset, so the
        // conversation scrolls behind them and the text box is ALWAYS visible — a tall team
        // recommendation card can no longer push the composer off-screen (the founder's bug).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // STATE strips keep their tinted treatment — things to resolve, not suggestions.
                if engineMissing { engineMissingCard }
                if let p = vm.needsReauth { reauthBanner(p) }
                if vm.mixedProvidersNote { mixedProvidersStrip }
                if !vm.deniedTools.isEmpty && !vm.isRunning { deniedStrip }
                if !vm.editedFiles.isEmpty { changedFilesStrip }
                if let error = vm.errorText { errorBanner(error) }
                // SUGGESTIONS collapse to ONE neutral coach at a time: the rich advisor card,
                // else a single CoachChip (team-fit / loop / repo), else a saving tip. Bounded
                // so a big card scrolls internally instead of shoving the composer down.
                Group {
                    if advisorCardVisible { advisorCard }
                    coachSlot
                    if let tip = saverTip, !advisorCardVisible, !hasCoachSuggestion {
                        TokenSaverBanner(tip: tip,
                                         onAction: { saverAction(tip) },
                                         onDismiss: { dismissedTips.insert(tip.kind) })
                            .padding(.horizontal, Space.m)
                            .padding(.top, Space.s)
                    }
                }
                inputBar
            }
            .background(.bar)
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

    /// A header action button: a 28×28 icon with a subtle rounded HOVER highlight + a
    /// tooltip, tinting coral when `active`. Gives every header control the same feedback.
    private func headerIcon(_ system: String, help: String, accessibility: String? = nil,
                            active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 14))
                .foregroundStyle(active ? Theme.accent : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTint(cornerRadius: Theme.rowCorner)
        .help(help)
        .accessibilityLabel(accessibility ?? help)
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                // Title row: the conversations toggle sits WITH the H1 (aligned to it, not
                // orphaned in the left margin). ⌘\; coral only when the list is open.
                HStack(spacing: Space.s) {
                    headerIcon("sidebar.leading", help: model.t("sidebar.toggle"), active: showSidebar) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showSidebar.toggle() }
                    }
                    .keyboardShortcut("\\", modifiers: .command)

                    // The chat title — the H1, editable inline.
                    TextField(model.t("chat.untitled"), text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.sfCardTitle)
                        .lineLimit(1)
                        .onSubmit { rename(editingTitle) }
                }

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
                        if MapStore.shared.maps.contains(where: { $0.repoPath == path }) {
                            Button { model.navSection = .map } label: {
                                Image(systemName: "circle.hexagongrid.fill")
                                    .font(.system(size: 11)).foregroundStyle(Theme.coral)
                            }
                            .buttonStyle(.plain)
                            .help(model.t("map.injected.help"))
                        }
                        if !shipTools.isEmpty {
                            Menu {
                                ForEach(shipTools) { tool in
                                    Button(model.t("ship.via", tool.displayName)) { shipTool = tool; showShipConfirm = true }
                                }
                            } label: {
                                Image(systemName: "paperplane").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help(model.t("ship.help"))
                        }
                    } else {
                        // No repo yet → a one-tap "connect a folder" right in the chat,
                        // so code work is reachable without hunting for it.
                        Button { _ = model.pickRepo(for: config.id) } label: {
                            Label(model.t("chat.connectRepo"), systemImage: "folder.badge.plus")
                                .font(.sfCaption2)
                        }
                        // Secondary (neutral): the coral-tinted "team" chip beside it is the one
                        // accent in this row — two coral links competing read as noise.
                        .buttonStyle(.plain).foregroundStyle(.secondary)
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
            // Plan headroom: your live Claude 5-hour rate-limit %, always visible while you
            // work (chat AND Code Mode share this header) — calm until you near the cap, then
            // amber/red. Tap → the Usage section. Renders nothing until the % is available.
            ClaudeUsagePill(style: .chip)
            // Mission report — the shareable summary of the finished run.
            if vm.hasFinishedActivity {
                headerIcon("flag.checkered", help: model.t("report.open"),
                           accessibility: model.t("report.title")) { showReport = true }
            }
            if codeModeEligible {
                headerIcon("chevron.left.forwardslash.chevron.right", help: model.t("chat.codeMode.help"),
                           accessibility: model.t("chat.codeMode"), active: codeMode) {
                    codeMode.toggle()
                    if codeMode { showActivity = false }   // one right-side slot, mutually exclusive
                }
            }
            headerIcon("sidebar.trailing", help: model.t("chat.activity.help"),
                       accessibility: model.t("chat.activity"), active: showActivity) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    showActivity.toggle()
                    if showActivity { codeMode = false }   // one right-side slot, mutually exclusive
                }
                if !showActivity { agentFocus = nil }
            }
            headerIcon("slider.horizontal.3", help: model.t("inspector.toggle"),
                       accessibility: model.t("chat.settings")) { showInspector = true }
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .frame(height: Theme.headerContentHeight)   // one fixed top-bar height (unified)
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

    @ViewBuilder
    private var messagesList: some View {
        if vm.messages.isEmpty {
            emptyState
        } else {
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
                        // NEVER render an EMPTY assistant bubble — neither the live one
                        // (activityRow covers it) nor the placeholders a failed/earlier
                        // turn leaves behind. Those stranded avatars were the "orbs
                        // parados de ejecuciones anteriores" scattered down the transcript.
                        let emptyAssistant = message.role == .assistant
                            && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if !emptyAssistant {
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
                    // Tappable team strip — reach EACH agent's live activity straight from the
                    // chat (no need to hunt for the side panel). Shows while a team runs or after.
                    if !config.strategy.subagentRoles.isEmpty, vm.isRunning || vm.hasFinishedActivity {
                        agentsStrip
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
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .frame(maxWidth: 560, alignment: .trailing)
                    // The user's turn: a QUIET chip — a whisper of coral tint over a neutral
                    // fill with ink text, not a saturated coral slab. The old bright-coral
                    // fill read as an alert/error and was the loudest thing on screen; calm
                    // chat UIs keep the user's own words near-neutral (ChatGPT/Claude).
                    // Coral is reclaimed for actions + the live agent moment, not chat history.
                    .background(
                        RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous)
                            .fill(Theme.coral.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous)
                                .strokeBorder(Theme.coral.opacity(0.16), lineWidth: 1)))
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
                            // While a meta turn orchestrates, this is the live narration (role
                            // chips + step lines + "Paso N/M") — text-first and legible, the
                            // pattern the founder liked. The topology lives in the panel's
                            // light stage, not as a dark canvas dropped into the transcript.
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
                                        ThinkingOrb(state: .solving, size: 14)
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

    /// Distinct glyphs per suggestion so the three cards read as different intents.
    private let suggestionIcons = ["doc.text.magnifyingglass", "list.bullet.rectangle", "text.book.closed"]

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: Space.xl)
            // The hero coral mark, seated in its OWN glow so it reads as emitting light into
            // the reef, not a thumbnail floating in a void — the app's "logo in motion".
            CoralSphere(size: 112)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.coral.opacity(0.22), .clear],
                                             center: .center, startRadius: 0, endRadius: 140))
                        .frame(width: 280, height: 280)
                        .blur(radius: 14)
                        .breathingGlow(color: Theme.coral)
                }
                .restingShadow(diameter: 112)
                .staggeredAppear(index: 0)
            // Hero greeting — big + tight so it dwarfs the body copy (a designed moment).
            (Text(chatGreeting).foregroundStyle(Theme.ink)
                + Text(".").foregroundStyle(Theme.coral))
                .font(.sfHero)
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640)
                .staggeredAppear(index: 1)
            Text(model.t("chat.empty"))
                .font(.sfSubtitle)
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
                    suggestionCard(key: key, icon: suggestionIcons[index])
                        .staggeredAppear(index: index + 4)
                }
            }
            .frame(maxWidth: 520)
            Spacer(minLength: Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, Space.l)
    }

    /// A crafted suggestion card: a coral IconBadge + the prompt + a quiet insert arrow, on
    /// an elevated card — reads as an invitation, not a triplicated list row.
    private func suggestionCard(key: String, icon: String) -> some View {
        Button { vm.input = model.t(key) } label: {
            HStack(spacing: Space.m) {
                IconBadge(systemName: icon)
                Text(model.t(key)).font(.sfCallout).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Space.s)
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryOnMaterial)
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.cardBg).elevation(.e1))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverLift()
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

    /// A horizontal, tappable strip of the team's agents — tap one to open its live activity
    /// (what it's doing / did), right from the chat. The active agent glows; done agents get a
    /// check. This is the "access each agent from the chat screen" affordance.
    private var agentsStrip: some View {
        let roles = config.strategy.subagentRoles
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(roles) { role in
                    let name = role.name
                    let running = vm.isRunning && (
                        vm.rolesInProgress.contains { AgentNameMatcher.titlesMatch($0, name) }
                        || (vm.rolesInProgress.isEmpty && AgentNameMatcher.titlesMatch(vm.activeSubagent ?? "", name)))
                    let count = vm.rolesRunning[name] ?? 0
                    Button {
                        agentFocus = .sub(name)
                        showActivity = true      // open the panel focused on this agent
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: role.role.icon).scaledFont(10).foregroundStyle(role.role.tint)
                            Text(name).font(.sfCaption2.weight(.medium)).lineLimit(1)
                            if running {
                                if count > 1 { Text("×\(count)").scaledFont(9, weight: .bold).foregroundStyle(Theme.tealText) }
                                Circle().fill(Theme.teal).frame(width: 5, height: 5)
                            } else if vm.hasFinishedActivity {
                                Image(systemName: "checkmark").scaledFont(8, weight: .bold).foregroundStyle(Theme.success)
                            }
                        }
                        .padding(.horizontal, Space.s).padding(.vertical, 4)
                        .background(Capsule().fill(running ? role.role.tint.opacity(0.14) : Theme.hairline.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(running ? role.role.tint.opacity(0.5) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(model.t("chat.agent.open", name))
                }
            }
            .padding(.horizontal, Space.xs)
        }
        .frame(maxWidth: 560)
    }

    private var activityRow: some View {
        HStack(spacing: Space.s) {
            // The "working" thought-orb (particles on tilted orbits) while a turn runs.
            ThinkingOrb(state: .working, size: 22)
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

    /// Mid-run "a provider's login went stale" → a one-tap Reconnect (in-app sign-in),
    /// then auto-retry the same turn. This is what turns a silent freeze into a self-heal.
    private func reauthBanner(_ provider: AIProvider) -> some View {
        HStack(spacing: Space.s) {
            Label(model.t("chat.reauth.needed", provider.displayName),
                  systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.sfCaption2).foregroundStyle(Theme.warningText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { reconnectingProvider = provider } label: {
                Label(model.t("chat.reconnect", provider.displayName), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.moon).controlSize(.small)
            Button { vm.needsReauth = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12))
        // Reconnect the SPECIFIC provider (worker or orchestrator) then re-run the turn.
        .sheet(item: $reconnectingProvider) { p in
            ProviderConnectSheet(provider: p) {
                vm.needsReauth = nil
                vm.retryAllowingAll()
            }
        }
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
            // .top so the text sits at the TOP of the box and the field grows DOWNWARD from
            // there (the founder found bottom-aligned text read as "stuck to the bottom").
            HStack(alignment: .top, spacing: Space.s) {
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
                // maxWidth:.infinity gives the field a BOUNDED width so a long line wraps
                // (instead of extending and getting clipped); 1...8 then grows the box with
                // the content up to 8 lines and scrolls internally beyond that — so you
                // never lose the line you're typing.
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1...8)
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
            isolationBar
            composerFooter
        }
        // Center the composer on the SAME reading measure as the messages, so the whole
        // conversation reads as one centred document; the `.bar` still spans full width.
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, alignment: .center)
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
        .sheet(isPresented: $showIsolationDiff) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.t("isolate.review")).font(.sfCardTitle)
                    Spacer()
                    Button(model.t("common.done")) { showIsolationDiff = false }.keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.m).background(.bar)
                ScrollView {
                    Text(isolationDiffText.isEmpty ? "—" : isolationDiffText)
                        .font(.sfCode).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.l)
                }
            }
            .frame(minWidth: 640, idealWidth: 820, minHeight: 400, idealHeight: 600)
            .background(Theme.appBg)
        }
        .task(id: config.repoPath) { shipTools = ShipService.available() }
        .confirmationDialog(model.t("ship.confirm.title", shipTool?.displayName ?? ""),
                            isPresented: $showShipConfirm, titleVisibility: .visible) {
            Button(model.t("ship.confirm.deploy"), role: .destructive) {
                guard let tool = shipTool, let repo = config.repoPath else { return }
                shipping = true; shipResult = nil; showShipResult = true
                Task { let r = await ShipService.deploy(tool, repo: repo); shipResult = r; shipping = false }
            }
            Button(model.t("ship.cancel"), role: .cancel) {}
        } message: { Text(model.t("ship.confirm.body")) }
        .sheet(isPresented: $showShipResult) { shipResultSheet }
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
                    grillToggle
                    approachesToggle
                    if config.repoPath?.isEmpty == false { isolateToggle }
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

    /// "Grill me first" — the agent interrogates you on edge cases before implementing.
    /// A calm toggle: coral when armed, neutral otherwise.
    private var grillToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { vm.grillMe.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist").font(.system(size: 10))
                Text(model.t("grill.label")).font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(vm.grillMe ? Theme.coral : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(vm.grillMe ? Theme.accentSoft : .clear))
        }
        .buttonStyle(.plain)
        .help(model.t("grill.help"))
        .accessibilityLabel(model.t("grill.label"))
    }

    /// "Approaches" — the agent proposes N distinct approaches to compare before implementing.
    private var approachesToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { vm.proposeApproaches.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2").font(.system(size: 10))
                Text(model.t("approaches.label")).font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(vm.proposeApproaches ? Theme.coral : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(vm.proposeApproaches ? Theme.accentSoft : .clear))
        }
        .buttonStyle(.plain)
        .help(model.t("approaches.help"))
        .accessibilityLabel(model.t("approaches.label"))
    }

    /// "Aislar" — run in a git worktree so autonomous edits don't touch the live tree until
    /// you review + merge. Coral when armed.
    private var isolateToggle: some View {
        Button { vm.requestIsolation() } label: {
            HStack(spacing: 4) {
                if vm.isolationBusy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                else { Image(systemName: vm.isolation != nil ? "shield.lefthalf.filled" : "shield").font(.system(size: 10)) }
                Text(model.t("isolate.label")).font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(vm.isolation != nil ? Theme.coral : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(vm.isolation != nil ? Theme.accentSoft : .clear))
        }
        .buttonStyle(.plain)
        .help(model.t("isolate.help"))
        .accessibilityLabel(model.t("isolate.label"))
    }

    /// The banner shown while a run is isolated: review the diff, merge it into the working
    /// tree, or discard it.
    @ViewBuilder private var isolationBar: some View {
        if vm.isolation != nil {
            HStack(spacing: Space.s) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.coral).font(.system(size: 11))
                Text(model.t("isolate.banner")).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                // While the independent review runs (a CLI pass over the diff — seconds to
                // a minute), show a live "reviewing… Xs" so it never looks stuck.
                if vm.isolationBusy {
                    HStack(spacing: 5) {
                        WorkingLogo(size: 12)
                        Text(model.t("isolate.verifying")).font(.sfCaption2).foregroundStyle(Theme.accent)
                        ElapsedText()
                    }
                } else {
                    isolationVerdict
                }
                Spacer()
                Button(model.t("isolate.verify")) { Task { await vm.verifyIsolation() } }
                    .controlSize(.small).disabled(vm.isolationBusy)
                Button(model.t("isolate.review")) {
                    Task { isolationDiffText = await vm.isolationDiff() ?? "—"; showIsolationDiff = true }
                }
                .controlSize(.small).disabled(vm.isolationBusy)
                Button(model.t("isolate.merge")) {
                    // Blast-radius gate: an irreversible change must be confirmed, never merged
                    // on one click. Contained/wide merge directly (still a manual human action).
                    if vm.isolationBlast?.radius == .irreversible { confirmIrreversibleMerge = true }
                    else { Task { await vm.mergeIsolation() } }
                }
                .buttonStyle(.moon).controlSize(.small).disabled(vm.isolationBusy)
                Button(model.t("isolate.discard"), role: .destructive) { Task { await vm.discardIsolation() } }
                    .controlSize(.small).disabled(vm.isolationBusy)
            }
            .padding(.horizontal, Space.m).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous).fill(Theme.accentSoft))
            .padding(.top, 4)
            .confirmationDialog(model.t("blast.merge.confirm.title"), isPresented: $confirmIrreversibleMerge,
                                titleVisibility: .visible) {
                Button(model.t("blast.merge.confirm.go"), role: .destructive) { Task { await vm.mergeIsolation() } }
                Button(model.t("ship.cancel"), role: .cancel) {}
            } message: {
                Text(model.t("blast.merge.confirm.body", vm.isolationBlast?.reasons.joined(separator: ", ") ?? ""))
            }
        }
    }

    /// The independent-verifier verdict on the isolated diff: a green seal when a different-family
    /// reviewer approves, an amber flag with the issue count otherwise.
    @ViewBuilder private var isolationVerdict: some View {
        HStack(spacing: Space.s) {
            // The blast-radius lane (gate on cost-to-undo, not on confidence): green=contained,
            // amber=wide, red=irreversible ("a human must look").
            if let blast = vm.isolationBlast { blastChip(blast) }
            if vm.isolationVerifyError != nil {
                Label(model.t("isolate.verify.fail"), systemImage: "exclamationmark.triangle")
                    .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
            } else if !vm.isolationJudges.isEmpty {
                let n = vm.isolationFindings.count
                let high = vm.isolationFindings.filter { $0.severity == .high }.count
                let judges = vm.isolationJudges.count
                let by = judges > 1 ? model.t("isolate.verified.panel", judges)
                                    : (vm.isolationVerifiedBy?.displayName ?? "")
                if n == 0 {
                    Label(judges > 1 ? by : model.t("isolate.verified", by), systemImage: "checkmark.seal.fill")
                        .font(.sfCaption2).foregroundStyle(Theme.success).lineLimit(1)
                        .help(vm.isolationJudges.map(\.displayName).joined(separator: " · "))
                } else {
                    Label(model.t("isolate.issues", n) + (high > 0 ? " ⚑\(high)" : ""), systemImage: "exclamationmark.triangle.fill")
                        .font(.sfCaption2).foregroundStyle(Theme.warning).lineLimit(1)
                        .help((judges > 1 ? by + "\n" : "")
                              + vm.isolationFindings.prefix(6).map { "• [\($0.severity.rawValue)] \($0.title)" }.joined(separator: "\n"))
                }
            }
        }
    }

    /// A small lane chip for the change's blast radius, with the "why" in a tooltip.
    private func blastChip(_ a: BlastAssessment) -> some View {
        let color: Color = a.radius == .irreversible ? Theme.danger
                         : (a.radius == .wide ? Theme.warning : Theme.success)
        let icon = a.radius == .irreversible ? "hand.raised.fill"
                 : (a.radius == .wide ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
        return Label(model.t(a.radius.labelKey), systemImage: icon)
            .font(.sfCaption2.weight(.medium)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14)))
            .help(a.reasons.isEmpty ? model.t("blast.\(a.radius.rawValue).help")
                                    : model.t("blast.why", a.reasons.joined(separator: ", ")))
    }

    /// Bet 4 — the thin "ship" result: progress while the deploy CLI runs, then the live
    /// URL (one-tap Open) and the full log. Never a PaaS — just the CLI's own output.
    @ViewBuilder private var shipResultSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(shipping ? model.t("ship.deploying", shipTool?.displayName ?? "")
                                : (shipResult?.ok == true ? model.t("ship.done") : model.t("ship.failed")),
                      systemImage: shipping ? "paperplane"
                                : (shipResult?.ok == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                    .font(.sfCardTitle)
                    .foregroundStyle(shipping ? Theme.accent : (shipResult?.ok == true ? Theme.success : Theme.warning))
                Spacer()
                if let url = shipResult?.url, let u = URL(string: url) {
                    Button {
                        NSWorkspace.shared.open(u)
                    } label: { Label(model.t("ship.open"), systemImage: "arrow.up.right.square") }
                }
                Button(model.t("common.done")) { showShipResult = false }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m).background(.bar)
            if shipping {
                VStack(spacing: Space.s) {
                    WorkingLine(label: model.t("ship.deploying", shipTool?.displayName ?? ""))
                    Text(model.t("ship.deploying.note")).font(.sfCaption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.l)
            } else {
                ScrollView {
                    Text(shipResult?.log.isEmpty == false ? shipResult!.log : "—")
                        .font(.sfCode).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.l)
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 360, idealHeight: 520)
        .background(Theme.appBg)
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
