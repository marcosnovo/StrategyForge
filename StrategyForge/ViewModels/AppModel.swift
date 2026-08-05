//
//  AppModel.swift
//  StrategyForge
//
//  The app's single source of truth: saved configurations, the current selection,
//  user settings, and the actions that drive generation. Persists to JSON in
//  Application Support and holds security-scoped access to chosen repo folders.
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Decodes and discards one element of an unkeyed container — used by the lossy array
/// decoders to advance past a malformed entry without failing the whole decode.
struct DecoderSkip: Decodable { init(from decoder: Decoder) throws {} }

@Observable
@MainActor
final class AppModel {

    // MARK: - State

    /// The chat collection lives in ChatListStore (#35 phase 5); these forwarders keep
    /// every call site (`configurations`, `configurations[i].x = y`, `selectedConfigID`,
    /// @Bindable bindings) working, and data.json still persists them via `configurations`.
    let chatList = ChatListStore()
    var configurations: [Configuration] {
        get { chatList.configurations }
        set { chatList.configurations = newValue }
    }
    var selectedConfigID: Configuration.ID? {
        get { chatList.selectedID }
        set {
            if newValue != chatList.selectedID {
                // The diff-review result is per-chat: never let chat A's findings keep
                // rendering under chat B's Code Mode (the panel reads the global slot).
                diffReview = nil
            }
            // The selected chat's ChatViewModel is built from its transcript on the
            // next render — make sure it's hydrated before that happens.
            if let id = newValue { hydrateTranscriptIfNeeded(id) }
            chatList.selectedID = newValue
        }
    }
    /// Tombstones for chats deleted on this device — persisted so sync deletes them from
    /// iCloud and never lets the remote copy resurrect them (bug: deletes came back).
    @ObservationIgnored var deletedConfigIDs: Set<UUID> = []
    /// Per-config `updatedAt` captured at the last successful sync — the baseline that
    /// lets the merge tell an independent local edit (real conflict) from a stale copy.
    @ObservationIgnored var syncBaseline: [UUID: Date] = [:]
    var settings = AppSettings()

    /// The team collection lives in TeamLibrary (#35 phase 3); these forwarders keep every
    /// call site (`savedTeams`, `selectedTeamID`, `draftTeam`, incl. `savedTeams[i].x = y`)
    /// working, and data.json still co-persists the teams via `savedTeams` below.
    let teamLibrary = TeamLibrary()
    /// Global library of named team presets, reusable across chats.
    var savedTeams: [SavedTeam] {
        get { teamLibrary.teams }
        set { teamLibrary.teams = newValue }
    }
    /// The team currently open in the Team section (independent of the selected chat).
    var selectedTeamID: SavedTeam.ID? {
        get { teamLibrary.selectedID }
        set { teamLibrary.selectedID = newValue }
    }

    /// A team being configured but NOT yet saved: picking a strategy opens this
    /// draft in the editor; it only joins `savedTeams` when the user hits "Create".
    /// Navigating away with a draft prompts a discard confirmation.
    var draftTeam: SavedTeam? {
        get { teamLibrary.draft }
        set { teamLibrary.draft = newValue }
    }
    /// A pending navigation deferred while the discard-draft confirmation is shown.
    @ObservationIgnored private var pendingLeave: (() -> Void)?
    /// Drives the "discard this draft team?" confirmation.
    var showDiscardDraftConfirm = false

    // MARK: - Providers
    /// The detected-CLIs state lives in ProviderRegistry (#35 phase 4); this forwarder
    /// keeps every `connectedProviders` call site working. Transient (not persisted).
    let providerRegistry = ProviderRegistry()
    var connectedProviders: Set<AIProvider> {
        get { providerRegistry.connected }
        set { providerRegistry.connected = newValue }
    }

    /// Re-show the first-run onboarding on demand (from the Lab), so it can be
    /// reviewed without wiping the `didOnboard` flag / reinstalling.
    var showOnboardingPreview = false

    /// Re-detect which provider CLIs are installed (off the main thread).
    func refreshConnectedProviders() async {
        await providerRegistry.refresh { [weak self] p in self?.settings.binary(for: p) ?? "" }
    }

    /// Whether a provider can be selected right now (its CLI is installed).
    func isConnected(_ provider: AIProvider) -> Bool { providerRegistry.isConnected(provider) }

    /// Connected providers whose STORED LOGIN looks expired or missing (a stronger signal than
    /// "CLI installed"). Surfaced as a "reconnect" hint so a stale login is caught BEFORE a run
    /// fails on it — this is what "Gemini conectado pero caducado" needed. Transient.
    var staleAuth: Set<AIProvider> = []

    /// Verify each connected provider's login freshness from disk (no subprocess, no Keychain
    /// prompt) and record which ones need reconnecting. Called at launch (splash) and on demand.
    func verifyConnections() async {
        let states = await ProviderAuth.verify(connectedProviders)
        let stale = Set(states.filter { $0.value == .expired || $0.value == .missing }.keys)
        staleAuth = stale
        for (p, s) in states where s == .expired || s == .missing {
            DiagnosticsLog.record("connection check: \(p.displayName) login \(s == .expired ? "expired" : "missing")", level: "WARN")
        }
    }

    /// Providers currently near their usage limit. The recommender steers role
    /// assignment AWAY from these when a comparable alternative exists (it never hard-
    /// excludes them — a capped provider is still used when it's the only real fit).
    /// Uses the same signals as the rail's usage card: Claude's real 5-hour / week
    /// rate-limit %, and Codex's plan %. Gemini exposes no usage, so it's never capped.
    var deprioritizedProviders: Set<AIProvider> {
        var set: Set<AIProvider> = []
        if let e = claudeExact, e.fiveHourPercent >= 85 || e.weekPercent >= 90 { set.insert(.claude) }
        if let c = codexUsage, let w = c.primary ?? c.secondary, w.usedPercent >= 85 { set.insert(.openai) }
        return set
    }

    // MARK: Provider plan (manual) + spend aggregation

    /// The user's declared plan for a provider (no CLI exposes it).
    func providerPlan(_ p: AIProvider) -> String? { settings.plan(for: p) }
    func setProviderPlan(_ plan: String?, for p: AIProvider) {
        settings.setPlan(plan, for: p); _ = save(stamp: false)
    }

    // MARK: Future-provider roadmap votes (local; no backend)

    /// Whether the user has upvoted a future provider on the "Coming soon" roadmap.
    func hasVotedFuture(_ id: String) -> Bool { settings.hasVotedFuture(id) }
    /// How many roadmap providers the user has voted for (for the honest local footer).
    var futureVoteCount: Int { settings.votedFutureProviders.count }
    /// Toggle the user's roadmap vote, persist locally, and (opt-in) log the demand.
    func toggleFutureVote(_ id: String) {
        let voted = settings.toggleFutureVote(id)
        _ = save(stamp: false)
        Analytics.log(.futureProviderVoted(id: id, voted: voted))
    }
    /// Record a free-text request for a provider not on the ballot.
    func requestFutureProvider(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.requestedProviders.append(trimmed)
        _ = save(stamp: false)
        Analytics.log(.futureProviderRequested(text: trimmed))
    }

    // MARK: OpenAI API key (Keychain) + runner config

    private static let openAIKeyItem = "openai.apiKey"

    /// The stored OpenAI API key (nil if none). Kept in the Keychain, never on disk.
    var openAIAPIKey: String? {
        KeychainStore.data(for: Self.openAIKeyItem).flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
    var hasOpenAIAPIKey: Bool { openAIAPIKey != nil }
    func setOpenAIAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { KeychainStore.delete(Self.openAIKeyItem) }
        else { KeychainStore.set(Data(trimmed.utf8), for: Self.openAIKeyItem) }
    }

    // MARK: Gemini API key (Keychain)

    private static let geminiKeyItem = "gemini.apiKey"

    /// The stored Gemini API key (nil if none). Google retired the free `gemini` CLI login,
    /// so a `GEMINI_API_KEY` from AI Studio is the one path that actually runs Gemini
    /// headless in Coral — kept in the Keychain, never on disk.
    var geminiAPIKey: String? {
        KeychainStore.data(for: Self.geminiKeyItem).flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
    var hasGeminiAPIKey: Bool { geminiAPIKey != nil }
    func setGeminiAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { KeychainStore.delete(Self.geminiKeyItem) }
        else { KeychainStore.set(Data(trimmed.utf8), for: Self.geminiKeyItem) }
    }

    /// API keys to hand the provider runner: OpenAI's (only in opt-in API mode, which re-enables
    /// Codex model choice) and Gemini's (always used when set — the retired free CLI has no other
    /// working headless path).
    func providerAPIKeys() -> [AIProvider: String] {
        var keys: [AIProvider: String] = [:]
        if settings.openaiUseAPIKey, let key = openAIAPIKey { keys[.openai] = key }
        if let g = geminiAPIKey { keys[.gemini] = g }
        return keys
    }

    /// CLI binary paths to hand a runner, read live from settings — the binaries
    /// analogue of `providerAPIKeys()` (every runner-construction site needs both).
    private var providerBinaries: [AIProvider: String] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { ($0, settings.binary(for: $0)) })
    }

    /// Providers whose CLI can't select a model, so the advisor must recommend only their
    /// account DEFAULT (not a specific one it would fail on). OpenAI/Codex on a ChatGPT
    /// login rejects `--model`; an API key re-enables model choice, so it's only locked
    /// without one. (Claude and Gemini accept a model on their normal logins.)
    var modelLockedProviders: Set<AIProvider> {
        providerAPIKeys()[.openai] == nil ? [.openai] : []
    }

    /// Per-provider spend rolled up from persisted chats. Claude carries real dollar
    /// cost + tokens (from Claude Code's result JSON); Codex/Gemini CLIs report no
    /// usage, so their tokens/cost are ~0 and only the chat count is meaningful.
    struct ProviderSpend: Identifiable { var provider: AIProvider; var tokens: Int; var costUSD: Double; var chats: Int
        var id: String { provider.rawValue } }
    func spendByProvider() -> [ProviderSpend] {
        var map: [AIProvider: ProviderSpend] = [:]
        for c in configurations {
            var s = map[c.provider] ?? ProviderSpend(provider: c.provider, tokens: 0, costUSD: 0, chats: 0)
            s.tokens += c.totalTokens; s.costUSD += c.totalCostUSD; s.chats += 1
            map[c.provider] = s
        }
        return AIProvider.allCases.map { map[$0] ?? ProviderSpend(provider: $0, tokens: 0, costUSD: 0, chats: 0) }
    }

    /// Which top-level section the nav rail shows: the chats, or connected services.
    /// `particleLab` is a DEBUG-only gallery for previewing the dot/particle motion
    /// system (spinners + waiting states) — its nav entry only appears in Debug builds.
    /// `code` is the repo-first door: connect a repo → work → PR (single-agent Claude).
    enum NavSection { case chats, services, team, usage, loops, particleLab, code, map, skills, memory, arena, settings }
    var navSection: NavSection = .chats

    /// The chat that should open directly in Code Mode (set by the Code launcher;
    /// ChatView consumes it once on appear).
    var openInCodeMode: Configuration.ID?

    // MARK: - Usage (real provider usage — extracted to UsageStore, #35 phase 2)
    /// Owns the usage state + refresh; these forwarders keep every call site
    /// (`model.claudeUsage`, `model.refreshUsage()`, …) working unchanged.
    let usageStore = UsageStore()
    var claudeUsage: UsageSummary? { usageStore.claudeUsage }
    var codexUsage: CodexUsage? { usageStore.codexUsage }
    var claudeExact: ClaudeUsageAPI.Exact? { usageStore.claudeExact }
    var isRefreshingUsage: Bool { usageStore.isRefreshingUsage }

    // MARK: - App updates
    /// A newer release than this build, when one is available (nil = up to date /
    /// offline). Drives the Settings "download" row and the nav-rail update dot.
    var availableUpdate: UpdateChecker.Update?

    /// Check GitHub Releases for a newer build. On automatic checks it flashes a
    /// one-time banner per new version; a manual check always reports the outcome.
    func checkForUpdates(manual: Bool = false) async {
        guard let update = await UpdateChecker.check() else {
            availableUpdate = nil
            if manual { flashSuccess(t("settings.updates.upToDate")) }
            return
        }
        availableUpdate = update
        let key = "update.notifiedVersion"
        let alreadyNotified = UserDefaults.standard.string(forKey: key) == update.version
        if manual || !alreadyNotified {
            UserDefaults.standard.set(update.version, forKey: key)
            flashSuccess(t("settings.updates.banner", update.version))
        }
    }

    /// Re-read usage from LOCAL LOGS only (Claude + Codex token counts) — no Keychain,
    /// so this is safe to call ambiently (activity panel, nav card) without triggering a
    /// login-Keychain password prompt. The exact rate-limit % (which needs the Claude
    /// Keychain token) is fetched separately, only on deliberate intent — see
    /// `refreshExactUsage()`. That's why the app no longer asks for the Keychain password
    /// on every launch.
    /// Forwarders to UsageStore (see #35 phase 2) — call sites are unchanged.
    func refreshUsage(includeExact: Bool = false) async {
        await usageStore.refreshUsage(includeExact: includeExact)
    }
    func refreshExactUsage(force: Bool = false) async {
        await usageStore.refreshExactUsage(force: force)
    }

    /// A CLI-backed single-shot runner configured from current settings — used by the
    /// eval engine (answer = editing off but not read-only; judge = readOnly, the
    /// independent grader). Reads binaries/keys/effort live from settings.
    func oneShotRunner(readOnly: Bool) -> CLIOneShotRunner {
        CLIOneShotRunner(
            binaries: providerBinaries,
            apiKeys: providerAPIKeys(),
            reasoningEffort: settings.codexReasoningEffort,
            readOnly: readOnly)
    }

    // MARK: - Code review (automated diff review — LangChain "software factory")
    /// The last review's findings (for the chat being viewed in Code mode). Transient.
    var diffReview: DiffReview?
    /// True while a review is in flight.
    var isReviewingDiff = false

    /// Review the working diff of a chat's repo with an INDEPENDENT read-only agent, so
    /// bugs/regressions surface before Commit + PR (reviewer ≠ author, applied to code).
    func reviewChanges(for config: Configuration) async {
        guard !isReviewingDiff else { return }   // one review at a time (the button is disabled too)
        guard let url = repoURL(for: config) else { return }
        isReviewingDiff = true
        defer { isReviewingDiff = false }
        let reviewedID = config.id
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let diff = await CodeGit.fullDiff(repo: url.path), !diff.isEmpty else {
            guard selectedConfigID == reviewedID else { return }   // user moved on mid-review
            diffReview = DiffReview(findings: [])   // nothing changed = clean
            flashSuccess(t("review.noChanges"))
            return
        }
        let review = await DiffReviewer.review(diff: diff, runner: oneShotRunner(readOnly: true))
        // The result belongs to the chat it was started from: if the user switched
        // chats while the reviewer ran, drop it rather than render it under (and
        // attribute it to) another chat's repo.
        guard selectedConfigID == reviewedID else { return }
        diffReview = review
        if let error = review.error {
            flashFailure(error)   // the reviewer never ran — not a clean verdict
        } else {
            flashSuccess(review.findings.isEmpty ? t("review.clean")
                                                 : t("review.foundIssues", review.findings.count))
        }
    }

    /// The service shown in the main area while in the Services section.
    var selectedService: AIProvider = .claude
    /// A developer TOOL (GitHub/Git) selected in the Services section — when set, the
    /// main area shows the tool's status/connect panel instead of an AI provider.
    var selectedTool: DevTool? = nil

    /// External developer tools the app relies on (bring-your-own-login CLIs), shown
    /// alongside the AI providers in Connected Services so their status isn't buried.
    enum DevTool: String, CaseIterable, Identifiable {
        case github, git
        var id: String { rawValue }
        var displayName: String { self == .github ? "GitHub" : "Git" }
    }

    // MARK: - UI layout state (restored across launches; see settings)
    /// The chat-list column is HIDDEN by default so an open chat gets the full centred
    /// reading column (ChatGPT-calm). The rail's Chats icon reveals/hides it on demand;
    /// it also auto-shows whenever no chat is selected (so New chat stays reachable).
    var showSidebar = false
    var showInspector = false
    /// The ⌘K command palette (chat/section quick-switcher) overlay.
    var showCommandPalette = false
    /// True while the window is in macOS full-screen. Drives the titlebar inset: in
    /// full-screen the traffic lights are hidden, so the 30pt top offset that clears them
    /// becomes dead space — the columns collapse it to a normal pad instead.
    var isFullScreen = false

    /// The top inset the columns/header use to clear the floating traffic lights —
    /// collapses to a normal pad in full-screen where there are none (design review D4).
    var titlebarTopInset: CGFloat { isFullScreen ? Space.s : Theme.titlebarInset }
    /// Right-side agent-activity panel visibility (persisted so it's restored).
    var showActivity = false {
        didSet { if showActivity != oldValue { settings.showActivity = showActivity; save(stamp: false) } }
    }

    /// The banner state + auto-dismiss now lives in BannerCenter (#35 extraction); these
    /// forwarders keep every existing call site (`model.banner`, `flashSuccess`, …) working.
    let bannerCenter = BannerCenter()
    typealias Banner = BannerCenter.Banner
    var banner: Banner? { bannerCenter.banner }

    /// Live security-scoped URLs from this session's folder pickers, keyed by the
    /// owning configuration id. Avoids re-resolving bookmarks mid-session. This is
    /// a transient cache, not UI state — kept out of observation so resolving a
    /// bookmark during a view's body (in `repoURL(for:)`) does not mutate observed
    /// state mid-render.
    @ObservationIgnored
    private var liveRepoURLs: [Configuration.ID: URL] = [:]

    // MARK: - Chat run lifetime (AppModel-owned VM cache)

    /// One ChatViewModel per chat, owned here (not by the view) so a running turn
    /// survives navigation away from the chat. Not observed: views get their VM
    /// through `chatViewModel(for:)`, and lazily filling this cache from a view
    /// body must not mutate observed state mid-render.
    @ObservationIgnored private var chatVMs: [Configuration.ID: ChatViewModel] = [:]
    /// MRU ring of recently-opened chats, so eviction keeps the last few resident (instant
    /// re-open) and releases the rest. Not observed; updated only from selection actions.
    @ObservationIgnored private var recentChatIDs: [Configuration.ID] = []

    #if DEBUG
    /// Test hook: which chats currently hold a resident ViewModel (for eviction tests).
    var _cachedChatVMIDs: Set<Configuration.ID> { Set(chatVMs.keys) }
    #endif
    /// Chats with a turn in flight (observed — drives global running indicators).
    /// Mutated only from `onRunningChanged` callbacks (action context), never
    /// from view-body paths.
    var runningChatIDs: Set<Configuration.ID> = []
    /// Chats that need the user's attention (a finished turn or a pending permission
    /// decision they weren't looking at). Drives a sidebar badge; also bounces the Dock.
    var attentionChatIDs: Set<Configuration.ID> = []

    /// Flag a chat as needing attention and — if the app is in the background — bounce
    /// the Dock so it's noticeable. `critical` keeps bouncing until the app is focused
    /// (used for a pending permission decision).
    func flagAttention(_ id: Configuration.ID, critical: Bool) {
        attentionChatIDs.insert(id)
        if !NSApp.isActive {
            NSApp.requestUserAttention(critical ? .criticalRequest : .informationalRequest)
        }
    }
    /// Clear a chat's attention flag (called when the user opens it).
    func clearAttention(_ id: Configuration.ID) {
        if attentionChatIDs.contains(id) { attentionChatIDs.remove(id) }
    }

    // MARK: - Advisor state (B3 — survives leaving the section)

    /// The task text typed into the Advisor (not persisted).
    var advisorTask = ""
    /// The Advisor's current recommendation (not persisted).
    var advisorAdvice: AdvisorEngine.Advice?

    /// Snapshot of the last persisted configurations, used to detect real content
    /// changes so `save()` bumps `updatedAt` only when something actually changed
    /// (drives last-writer-wins sync). Not observed.
    @ObservationIgnored private var savedSnapshot: [Configuration.ID: Configuration] = [:]

    // MARK: - Init

    /// Base directory for this model's on-disk state (data.json + transcript/activity
    /// sidecars). Injectable so tests can point at a temp dir instead of the real
    /// Application Support — the testability seam (#12). Defaults to the app's real dir.
    @ObservationIgnored let storeDirectory: URL

    /// Presents open/save panels (#12 seam) — real AppKit by default; a fake in tests
    /// returns a preset URL so folder/file-picking code runs without a modal.
    @ObservationIgnored let filePanels: FilePanelPresenting

    init(storeDirectory: URL = AppPaths.supportDirectory(), autoLoad: Bool = true,
         filePanels: FilePanelPresenting? = nil) {
        self.storeDirectory = storeDirectory
        self.filePanels = filePanels ?? AppKitFilePanels()
        if autoLoad { load() }
    }

    // MARK: - Localization

    /// The resolved language code ("en" or "es").
    var langCode: String {
        switch settings.language {
        case .system:
            let sys = Locale.current.language.languageCode?.identifier ?? "en"
            return sys == "es" ? "es" : "en"
        case .en: return "en"
        case .es: return "es"
        }
    }

    /// Localized string for a key.
    func t(_ key: String) -> String {
        L10n.string(key, langCode: langCode)
    }

    /// Localized, formatted string for a key with arguments.
    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: L10n.string(key, langCode: langCode), arguments: args)
    }

    // MARK: - Localized display for model content

    /// Stable key prefix for a built-in strategy, derived from its English name.
    private func strategyKey(_ name: String) -> String? {
        let n = name.lowercased()
        // "Solo · Economy" also contains "solo" — economy must match FIRST, or the
        // picker shows two rows with identical names/descriptions.
        if n.contains("economy") { return "strat.economy" }
        if n.contains("explore") && n.contains("plan") { return "strat.pipeline" }
        if n.contains("fan-out") && n.contains("worker") { return "strat.fanout" }
        if n.contains("advisor") { return "strat.execadv" }
        if n.contains("scout") { return "strat.scout" }
        if n.contains("triage") { return "strat.triage" }
        if n.contains("planner") { return "strat.planner" }
        if (n.contains("root") && n.contains("cause")) || n.contains("debug") { return "strat.rootcause" }
        if n.contains("specialist") { return "strat.domain" }
        if n.contains("research") { return "strat.research" }
        if n.contains("debate") || n.contains("consensus") { return "strat.debate" }
        if n.contains("sparring") { return "strat.sparring" }
        if n.contains("solo") { return "strat.solo" }
        return nil
    }

    func strategyDisplayName(_ strategy: Strategy) -> String {
        guard let key = strategyKey(strategy.name) else { return strategy.name }
        return t(key + ".name")
    }

    func strategyDisplayDescription(_ strategy: Strategy) -> String {
        guard let key = strategyKey(strategy.name) else { return strategy.description }
        return t(key + ".desc")
    }

    func roleKindName(_ kind: RoleKind) -> String {
        t("role.kind." + kind.rawValue)
    }

    // MARK: - Beginner guidance

    /// Strategies simple enough to recommend to a newcomer.
    private static let beginnerKeys: Set<String> = ["strat.solo", "strat.economy", "strat.execadv", "strat.planner"]

    func isBeginnerStrategy(_ strategy: Strategy) -> Bool {
        guard let key = strategyKey(strategy.name) else { return false }
        return Self.beginnerKeys.contains(key)
    }

    func strategyGoodFor(_ strategy: Strategy) -> String {
        guard let key = strategyKey(strategy.name) else { return "" }
        return t(key + ".good")
    }

    func strategyNotFor(_ strategy: Strategy) -> String {
        guard let key = strategyKey(strategy.name) else { return "" }
        return t(key + ".not")
    }

    /// A derived one-line description of HOW a strategy is triggered — the assistant
    /// explainer's TRIGGER row, mirroring the loops legend so both surfaces feel like
    /// one system. Pure function over the roles, so it works for custom strategies too.
    func strategyTriggerLine(_ strategy: Strategy) -> String {
        let subs = strategy.subagentRoles
        if subs.isEmpty { return t("strat.trigger.oneShot") }
        if subs.contains(where: { $0.role == .advisor }) { return t("strat.trigger.everyTurn") }
        return t("strat.trigger.cycle")
    }

    /// A derived one-line description of a strategy's TOPOLOGY (the RULE row): what
    /// shape the team is, named in plain language from the roles.
    func strategyTopologyLine(_ strategy: Strategy) -> String {
        let subs = strategy.subagentRoles
        let total = subs.reduce(0) { $0 + $1.count }
        if subs.isEmpty { return t("strat.topo.solo") }
        if subs.contains(where: { $0.role == .advisor }) { return t("strat.topo.advisor") }
        if subs.contains(where: { $0.role == .planner }) && subs.contains(where: { $0.role == .reviewer }) {
            return t("strat.topo.plannerReview")
        }
        if subs.allSatisfy({ $0.role == .specialist }) { return t("strat.topo.specialists", subs.count) }
        return t("strat.topo.fanout", total)
    }

    /// A 1-2 word task category ("Debug", "Explore", …) for the strategy chooser.
    func strategyTaskTag(_ strategy: Strategy) -> String {
        guard let key = strategyKey(strategy.name) else { return "" }
        return t(key + ".tag")
    }

    // MARK: - Topic buckets (strategy chooser filter)

    /// Everyday "what do you want to do" buckets used to orient the strategy picker.
    enum TopicBucket: String, CaseIterable, Identifiable {
        case write, understand, code, faster, decide, pressure
        var id: String { rawValue }
        var labelKey: String { "picker.bucket.\(rawValue)" }
        var icon: String {
            switch self {
            case .write: return "pencil.and.outline"
            case .understand: return "lightbulb.max"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .faster: return "square.stack.3d.up"
            case .decide: return "arrow.triangle.branch"
            case .pressure: return "shield.lefthalf.filled"
            }
        }
        /// The strategyKey of the single best strategy for this bucket.
        var recommendedKey: String {
            switch self {
            case .write: return "strat.execadv"
            case .understand: return "strat.research"
            case .code: return "strat.planner"
            case .faster: return "strat.fanout"
            case .decide: return "strat.debate"
            case .pressure: return "strat.sparring"
            }
        }
    }

    /// Buckets a strategy belongs to (soft, overlapping — a lens, not a partition).
    func strategyBuckets(_ strategy: Strategy) -> Set<TopicBucket> {
        switch strategyKey(strategy.name) {
        case "strat.execadv":   return [.write, .faster]
        case "strat.research":  return [.understand]
        case "strat.planner":   return [.code, .faster]
        case "strat.fanout":    return [.faster]
        case "strat.debate":    return [.decide]
        case "strat.sparring":  return [.pressure]
        case "strat.scout":     return [.code, .understand, .faster]
        case "strat.triage":    return [.faster]
        case "strat.rootcause": return [.code, .pressure]
        case "strat.domain":    return [.code, .faster]
        case "strat.solo":      return [.write, .understand, .decide, .faster]
        default:                return []
        }
    }

    /// True when this strategy is the recommended one for the given bucket.
    func isRecommended(_ strategy: Strategy, for bucket: TopicBucket) -> Bool {
        strategyKey(strategy.name) == bucket.recommendedKey
    }

    // MARK: - Banner helper

    /// Public helper for views to show an auto-dismissing success banner.
    func flashSuccess(_ message: String) { bannerCenter.success(message) }

    /// Public helper for views/services to show a sticky failure banner (also logged).
    func flashFailure(_ message: String) { bannerCenter.failure(message) }

    /// True while the current banner is a failure — the capsule then offers the
    /// "Export log" / "Fix" actions.
    var bannerIsFailure: Bool { bannerCenter.isFailure }

    /// Save the diagnostics log to a user-chosen file (for sharing when something
    /// went wrong). Shared by Settings and the failure banner.
    func exportDiagnostics() {
        let contents = DiagnosticsLog.contents()
        guard let url = filePanels.save(suggestedName: "coral-diagnostics.txt", contentTypes: [.plainText]) else { return }
        do {
            try (contents.isEmpty ? t("settings.diagnostics.empty") : contents)
                .write(to: url, atomically: true, encoding: .utf8)
            flashSuccess(t("settings.diagnostics.exported"))
        } catch {
            show(.failure(t("settings.diagnostics.exportFailed")))
        }
    }

    /// Jump to Connected Services (the usual fix for a provider run failure).
    func openConnectedServices() {
        dismissBanner()
        navSection = .services
    }

    /// Dismiss the current banner (the capsule's close button).
    func dismissBanner() { bannerCenter.dismiss() }

    /// Forwarder so AppModel's own `show(.success/.failure(...))` call sites are unchanged.
    private func show(_ banner: Banner) {
        bannerCenter.show(banner)
    }

    // MARK: - Selection helpers

    var selectedConfiguration: Configuration? {
        configurations.first { $0.id == selectedConfigID }
    }

    /// A stable two-way binding to a configuration by id, for the editor.
    func configurationBinding(_ id: Configuration.ID) -> Binding<Configuration> {
        Binding(
            get: { self.configurations.first(where: { $0.id == id })
                ?? Configuration(name: "", strategy: StrategyLibrary.solo()) },
            set: { newValue in
                if let i = self.configurations.firstIndex(where: { $0.id == id }) {
                    self.configurations[i] = newValue
                }
            }
        )
    }

    // MARK: - Configuration lifecycle

    /// Create a new configuration seeded with the first template and select it.
    func addConfiguration() {
        // A new chat: empty name (shows the "New chat" placeholder and enables
        // auto-titling from the first message). The team is left "auto": the first
        // message recommends one from the prompt (executorAdvisor is only the
        // provisional placeholder used if the user never types anything).
        let config = Configuration(
            name: "",
            strategy: StrategyLibrary.executorAdvisor(),
            lastActiveAt: Date(),   // newest chat sorts to the top
            strategyIsAuto: true
        )
        configurations.append(config)
        selectedConfigID = config.id
        save()
    }

    /// Start a new chat pinned to a specific provider and jump to it (used by the
    /// Connections "Used by" empty state — one tap from a provider to a chat on it).
    func addConfiguration(provider: AIProvider) {
        let config = Configuration(
            name: "",
            strategy: StrategyLibrary.executorAdvisor(),
            provider: provider,
            lastActiveAt: Date(),
            strategyIsAuto: true
        )
        configurations.append(config)
        selectedConfigID = config.id
        navSection = .chats
        save()
    }

    /// Start a new chat already bound to `repoURL` and jump to it — used by the Map's
    /// "Open in chat"/"Ask about this node", so the code-map digest auto-injects on the first
    /// turn of that session. An optional `draft` seeds the composer (e.g. a question about a node).
    func addConfiguration(repoURL: URL, draft: String = "") {
        var config = Configuration(
            name: repoURL.lastPathComponent,
            strategy: StrategyLibrary.executorAdvisor(),
            lastActiveAt: Date(),
            strategyIsAuto: true,
            draft: draft
        )
        config.repoPath = repoURL.path
        config.repoBookmark = try? repoURL.bookmarkData(options: [.withSecurityScope],
                                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        configurations.append(config)
        selectedConfigID = config.id
        navSection = .chats
        save()
    }

    /// Token Saver: start a fresh chat that keeps a chat's team, provider and
    /// repo binding but drops the transcript (the token furnace). An optional
    /// summary is seeded as the draft so context carries forward for a few
    /// hundred tokens instead of a full history re-read.
    func startFreshChat(from id: Configuration.ID, summary: String? = nil) {
        guard let source = configurations.first(where: { $0.id == id }) else { return }
        // Inherit a descriptive name (so it's not titled from the summary preamble)
        // and mark it a continuation of the source — both the title and the sidebar
        // link make clear this chat comes from the other.
        let base = source.name.trimmingCharacters(in: .whitespaces)
        let inheritedName = base.isEmpty ? "" : t("chat.continued", base)
        let fresh = Configuration(
            name: inheritedName,
            strategy: source.strategy,
            provider: source.provider,
            repoPath: source.repoPath,
            repoBookmark: source.repoBookmark,
            lastActiveAt: Date(),
            titleWasManuallySet: !inheritedName.isEmpty,
            draft: summary ?? "",
            continuedFrom: source.id
        )
        configurations.append(fresh)
        selectedConfigID = fresh.id
        save()
    }

    /// Manually rename a chat. Portable content → save WITH a stamp. Marks the
    /// title as user-set so auto-titling stops.
    func renameConfiguration(_ id: Configuration.ID, _ title: String) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        configurations[i].name = name
        configurations[i].titleWasManuallySet = true
        // Keep any loop that came from this chat labelled with its current name.
        LoopStore.shared.updateSourceName(forChat: id, to: name)
        save()
    }

    /// Name an untitled chat by inferring a concise topic from its first user
    /// message. No-op if the user already named it or a name exists.
    func autoTitleIfNeeded(_ id: Configuration.ID, fromFirstMessage text: String) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        guard !configurations[i].titleWasManuallySet, configurations[i].name.isEmpty else { return }
        let title = titleFromMessage(text)
        guard !title.isEmpty else { return }
        configurations[i].name = title   // leave titleWasManuallySet false (still auto)
        save()
    }

    /// A descriptive title for a chat — the SUBJECT of the first message, not just a
    /// bare category. "Research" alone can't tell two research chats apart, so we
    /// title with the cleaned-up topic ("Competitive app market research") and only
    /// fall back to a category word for very terse prompts that carry no subject.
    func titleFromMessage(_ text: String) -> String {
        let inferred = Self.inferredTitle(from: text)
        // Descriptive enough to distinguish chats → use it.
        if inferred.count >= 14 { return inferred }
        // Very short prompt → a category word beats a 2-word fragment.
        if let key = Self.topicCategoryKey(for: text) { return t(key) }
        return inferred
    }

    /// Map a message to a topic-category key ("topic.*"), or nil. Strategy: the
    /// leading action verb carries the intent ("Revisa…" = Review even if it also
    /// mentions "errores"), so we scan the FIRST few words first; only if nothing
    /// matches there do we scan the whole message. Stems are accent- and language-
    /// tolerant (Spanish + English), matched case-insensitively.
    static func topicCategoryKey(for text: String) -> String? {
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        // Intent verbs (Review/Research…) come BEFORE Bug fix so an incidental
        // "error"/"falla" in a review or research request doesn't hijack the title.
        let table: [(key: String, stems: [String])] = [
            ("topic.review",  ["revis", "review", "audit", "comprob", "verif", "evalú", "evalua", "repasa", "repás"]),
            ("topic.research",["investig", "explor", "analiz", "research", "entend", "entiend", "understand", "estudi", "averigu", "descubr"]),
            ("topic.explain", ["explic", "explíc", "cómo funciona", "como funciona", "how does", "qué hace", "que hace", "walk me through"]),
            ("topic.design",  ["diseñ", "rediseñ", "design", "interfaz", "ui/ux", " ui ", " ux ", "visual", "estétic", "estetic", "maquet", "layout", "look and feel"]),
            ("topic.refactor",["refactor", "reorganiz", "reestructur", "restructur", "limpia el códig", "limpiar el códig", "clean up"]),
            ("topic.perf",    ["optimiz", "rendimiento", "performance", "velocidad", "más rápid", "mas rapid", "lento", "latenc"]),
            // "documento" (the object) must NOT trigger docs — only writing docs does.
            ("topic.docs",    ["documenta", "documentaci", "readme", " docs", "docstring", "javadoc"]),
            ("topic.tests",   ["test", "prueb", "testea", "cobertura", "unit test", "xctest"]),
            ("topic.plan",    ["planific", "planea", "roadmap", "estrategia", "hoja de ruta", "plan de"]),
            ("topic.bugfix",  ["bug", "crash", "arregl", "soluciona", "corrig", "rompe", "roto", "no funciona", "broken", "peta", "fix "]),
            ("topic.feature", ["implement", "añad", "agreg", "crea ", "crear", "add ", "build", "desarroll", "nueva func", "feature", "construye"]),
        ]
        func firstMatch(in haystack: String) -> String? {
            for entry in table where entry.stems.contains(where: { haystack.contains($0) }) {
                return entry.key
            }
            return nil
        }
        // 1) Leading words (intent). 2) Whole message (fallback).
        let head = s.split(separator: " ").prefix(5).joined(separator: " ")
        return firstMatch(in: head) ?? firstMatch(in: s)
    }

    /// Re-derive titles for chats that were auto-named (never set by the user),
    /// upgrading legacy "Quiero…"-style truncations to the cleaner inferred topic.
    /// Idempotent: a well-formed title re-derives to itself, so this causes no churn.
    func retitleAutoNamedChats() {
        var changed = false
        for i in configurations.indices where !configurations[i].titleWasManuallySet {
            guard let firstUser = configurations[i].transcript.first(where: { $0.role == .user })?.text,
                  !firstUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let title = titleFromMessage(firstUser)
            if !title.isEmpty && title != configurations[i].name {
                configurations[i].name = title
                changed = true
            }
        }
        if changed { save(stamp: false) }   // cosmetic re-derive → don't bump sync clocks
    }

    /// Turn a free-text first message into a short topic title: strip leading
    /// filler ("Quiero…", "Necesito…", "Can you…"), drop trailing punctuation, and
    /// cut on a word boundary so nothing reads as a mangled sentence fragment.
    static func inferredTitle(from raw: String, maxChars: Int = 46) -> String {
        var s = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        guard !s.isEmpty else { return "" }

        // Leading filler to peel off (lowercased, longest first so multi-word wins).
        let fillers = [
            "me gustaría que", "me gustaria que", "me gustaría", "me gustaria",
            "necesito que", "quiero que", "quisiera que", "podrías", "podrias",
            "puedes", "podemos", "ayúdame a", "ayudame a", "ayúdame", "ayudame",
            "vamos a", "hay que", "tengo que", "necesito", "quiero", "quisiera",
            "por favor", "porfa", "oye", "hola",
            "i want to", "i need to", "i'd like to", "i would like to",
            "can you", "could you", "please help me", "please", "help me", "let's", "lets",
        ].sorted { $0.count > $1.count }

        var changed = true
        let strip = CharacterSet(charactersIn: " ,:;-–—.")
        while changed {
            changed = false
            let lower = s.lowercased()
            for f in fillers where lower.hasPrefix(f + " ") || lower == f {
                s = String(s.dropFirst(f.count)).trimmingCharacters(in: strip)
                changed = true
                break
            }
        }
        s = s.trimmingCharacters(in: strip)
        guard !s.isEmpty else { return String(raw.prefix(maxChars)) }

        // Capitalize the first letter, keep the rest as written.
        s = s.prefix(1).uppercased() + s.dropFirst()

        // Cut on a word boundary if too long.
        if s.count > maxChars {
            let head = String(s.prefix(maxChars))
            if let sp = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: sp) > maxChars / 2 {
                s = String(head[..<sp]) + "…"
            } else {
                s = head + "…"
            }
        }
        return s
    }

    /// Chats deleted in the last ~10s, kept in memory (the config with its transcript) so
    /// the "Undo" banner can restore them. The IRREVERSIBLE parts (sidecar deletion,
    /// continuedFrom cleanup) are deferred until the window closes; the tombstone is set
    /// now to prevent a mid-window sync resurrecting the chat, and undone on Undo.
    @ObservationIgnored private var pendingHardDelete: [Configuration.ID: (config: Configuration, task: Task<Void, Never>)] = [:]

    /// How long a deleted chat stays restorable. The deferred hard delete AND the
    /// banner's Undo button both use this constant, so the affordance can never
    /// outlive (or die before) the window it triggers.
    static let undoWindow: Duration = .seconds(10)

    func deleteConfiguration(_ id: Configuration.ID) {
        hydrateTranscriptIfNeeded(id)   // the in-memory undo copy must carry the full transcript
        guard let removed = configurations.first(where: { $0.id == id }) else { return }
        invalidateChatVM(id)
        configurations.removeAll { $0.id == id }
        deletedConfigIDs.insert(id)   // tombstone now → a sync in the window can't resurrect it
        liveRepoURLs[id] = nil
        if selectedConfigID == id { selectedConfigID = configurations.first?.id }
        // Defer the irreversible cleanup so a mis-click can be undone for 10s.
        let task = Task { @MainActor in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self.finalizeDelete(id)
        }
        pendingHardDelete[id] = (removed, task)
        save()   // data.json drops the chat; its sidecars stay on disk until finalize
        bannerCenter.showWithUndo(t("chat.deleted"), undoLabel: t("banner.undo"),
                                  dismissAfter: Self.undoWindow) { [weak self] in
            self?.undoDelete(id)
        }
    }

    /// The point of no return: clear dangling links + delete the sidecars.
    private func finalizeDelete(_ id: Configuration.ID) {
        guard pendingHardDelete.removeValue(forKey: id) != nil else { return }
        for i in configurations.indices where configurations[i].continuedFrom == id {
            configurations[i].continuedFrom = nil
        }
        discardPendingTranscriptWrites(id)   // a straggler must not resurrect the sidecar
        try? FileManager.default.removeItem(at: activityURL(id))     // drop the history sidecar
        try? FileManager.default.removeItem(at: transcriptURL(id))   // and the transcript sidecar
        save()
    }

    /// Restore a chat deleted within the undo window (its transcript is still in memory
    /// and its sidecars were never touched).
    func undoDelete(_ id: Configuration.ID) {
        guard let pending = pendingHardDelete.removeValue(forKey: id) else { return }
        pending.task.cancel()
        deletedConfigIDs.remove(id)          // un-tombstone
        if !configurations.contains(where: { $0.id == id }) {
            configurations.append(pending.config)
        }
        selectedConfigID = id
        save()
    }

    /// Duplicate a configuration (fresh id + name suffix). The copy keeps the same
    /// repo binding so re-generating into the same repo is one click away.
    func duplicateConfiguration(_ id: Configuration.ID) {
        hydrateTranscriptIfNeeded(id)   // the copy snapshots the source's transcript
        guard let source = configurations.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " " + t("config.copySuffix")
        copy.updatedAt = .distantPast   // will be stamped on save
        copy.lastGeneratedAt = nil
        if let idx = configurations.firstIndex(where: { $0.id == id }) {
            configurations.insert(copy, at: configurations.index(after: idx))
        } else {
            configurations.append(copy)
        }
        selectedConfigID = copy.id
        // The copy carries the source's transcript in memory — write its sidecar (on
        // this thread, so it exists before the transcript-stripped data.json save
        // lands; else it'd be lost on reload).
        if !copy.transcript.isEmpty { writeTranscript(copy.id, copy.transcript, sync: true) }
        save()
    }

    /// Import an existing repo's `.claude/` config back into an editable Strategy,
    /// binding the new configuration to that repo (so it round-trips / re-exports).
    func importFromRepo() {
        guard let url = filePanels.chooseDirectory(prompt: t("common.choose"),
                                                   message: t("import.pickMessage"),
                                                   startingAt: resolvedDefaultReposURL()) else { return }

        guard let strategy = repoStrategy(at: url) else {
            show(.failure(t("import.notFound")))
            return
        }
        var config = Configuration(name: strategy.name, strategy: strategy, repoPath: url.path)
        config.repoBookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
        configurations.append(config)
        selectedConfigID = config.id
        liveRepoURLs[config.id] = url
        save()
        flashSuccess(t("import.done", strategy.subagentRoles.count))
    }

    /// Parse a folder's `.claude/` (agents + CLAUDE.md) into a Strategy, or nil if
    /// the folder has no Claude Code config. Handles security-scoped access.
    func repoStrategy(at url: URL) -> Strategy? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let agentsDir = url.appendingPathComponent(".claude/agents", isDirectory: true)
        var agentFiles: [ClaudeConfigParser.AgentFile] = []
        if let entries = try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil) {
            for entry in entries where entry.pathExtension == "md" {
                if let contents = try? String(contentsOf: entry, encoding: .utf8) {
                    agentFiles.append(.init(fileName: entry.lastPathComponent, contents: contents))
                }
            }
        }
        let claudeMd = try? String(contentsOf: url.appendingPathComponent(ClaudeMdGenerator.fileName), encoding: .utf8)
        guard !agentFiles.isEmpty || claudeMd != nil else { return nil }
        return ClaudeConfigParser.parse(
            agentFiles: agentFiles.sorted { $0.fileName < $1.fileName },
            claudeMd: claudeMd,
            fallbackName: url.lastPathComponent)
    }

    /// "Drag your repo and visualize your setup" → import a folder's `.claude/` as a
    /// new team (the onboarding hook). Returns whether it found a config.
    @discardableResult
    func importTeamFromRepo(at url: URL) -> Bool {
        guard let strategy = repoStrategy(at: url) else {
            show(.failure(t("import.notFound")))
            return false
        }
        _ = createTeam(from: strategy, named: strategy.name)
        Analytics.log(.strategyImported(kind: "repo"))
        flashSuccess(t("import.done", strategy.subagentRoles.count))
        return true
    }

    /// Pick a repo folder and import its `.claude/` config as a new team.
    func importTeamFromRepoPanel() {
        guard let url = filePanels.chooseDirectory(prompt: t("common.choose"),
                                                   message: t("import.pickMessage"),
                                                   startingAt: resolvedDefaultReposURL()) else { return }
        importTeamFromRepo(at: url)
    }

    // MARK: - Strategy document (.sfstrategy) export / import

    /// Export a configuration's strategy as a shareable `.sfstrategy` document
    /// (topology only — never repo paths/bookmarks).
    func exportStrategyDocument(_ config: Configuration) {
        exportStrategyFile(config.strategy, logShare: false)
    }

    /// The one exporter behind `exportStrategyDocument` / `exportTeamDocument`:
    /// save panel → atomic write → redaction-aware flash. Only the team path logs
    /// a share (`logShare`), matching the two former near-copies exactly.
    private func exportStrategyFile(_ strategy: Strategy, logShare: Bool) {
        guard let url = filePanels.save(suggestedName: StrategyPackage.fileName(for: strategy),
                                        contentTypes: [.sfStrategy]) else { return }
        do {
            try StrategyPackage.export(strategy).write(to: url, options: .atomic)
            if logShare { Analytics.log(.strategyShared(kind: "file")) }
            flashSuccess(t(StrategyPackage.hasRedactableSecrets(strategy)
                           ? "doc.exportedRedacted" : "doc.exported"))
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
        }
    }

    /// Import a `.sfstrategy` document as a new (repo-less) configuration.
    func importStrategyDocument() {
        guard let url = filePanels.chooseFile(contentTypes: [.sfStrategy], prompt: t("common.choose")) else { return }
        do {
            let data = try Data(contentsOf: url)
            let strategy = try StrategyPackage.import(data).autoFixed()   // apply safe fixes
            // Reject structurally-broken imports (e.g. no orchestrator) instead of
            // adding an unusable strategy that would fail to generate/run.
            guard strategy.isValid, !strategy.roles.isEmpty else {
                show(.failure(t("doc.importInvalid")))
                return
            }
            let config = Configuration(name: strategy.name, strategy: strategy)
            configurations.append(config)
            selectedConfigID = config.id
            save()
            flashSuccess(t("doc.imported"))
        } catch {
            show(.failure(t("doc.importFailed", error.localizedDescription)))
        }
    }

    /// Apply the strategy's safe auto-fixes to a configuration (lint "fix all").
    func autoFixStrategy(_ id: Configuration.ID) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].strategy = configurations[i].strategy.autoFixed()
        save()
        flashSuccess(t("lint.fixedAll"))
    }

    /// Swap the strategy of a configuration for a fresh template instance.
    func applyTemplate(_ template: Strategy, to id: Configuration.ID) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        let prev = configurations[i].strategy
        let prevAuto = configurations[i].strategyIsAuto
        configurations[i].strategy = template
        configurations[i].strategyIsAuto = false   // user/AI chose a team explicitly
        save()   // persist the strategy change so it survives relaunch
        announceTeamSwap(t("team.applied", strategyDisplayName(template)),
                         id: id, previous: prev, previousAuto: prevAuto)
    }

    /// Banner for a team swap: a plain success when there was no real team to lose
    /// (fresh/auto chat), else a 10s Undo that restores the previous team — the same
    /// affordance as chat delete, so a mis-swap is never destructive.
    private func announceTeamSwap(_ message: String, id: Configuration.ID,
                                  previous: Strategy, previousAuto: Bool) {
        if previousAuto {
            flashSuccess(message)
        } else {
            bannerCenter.showWithUndo(message, undoLabel: t("banner.undo"),
                                      dismissAfter: Self.undoWindow) { [weak self] in
                self?.restoreStrategy(id, previous, wasAuto: previousAuto)
            }
        }
    }

    /// Restore a team swapped within the undo window.
    func restoreStrategy(_ id: Configuration.ID, _ strategy: Strategy, wasAuto: Bool) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].strategy = strategy
        configurations[i].strategyIsAuto = wasAuto
        save()
        flashSuccess(t("team.reverted"))
    }

    /// Add a fresh worker role to a chat's team (visual Team canvas CRUD). Returns
    /// the new role's id so the UI can select it.
    @discardableResult
    func addRole(to id: Configuration.ID) -> AgentRole.ID? {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return nil }
        // A unique slug: agent, agent-2, agent-3, …
        let existing = Set(configurations[i].strategy.roles.map(\.name))
        var name = "agent"
        var n = 2
        while existing.contains(name) { name = "agent-\(n)"; n += 1 }
        let role = AgentRole(
            name: name,
            role: .worker,
            model: .sonnet5,
            systemPrompt: "",
            description: t("team.newRole.description"),
            count: 1)
        configurations[i].strategy.roles.append(role)
        save()
        return role.id
    }

    /// Remove a role from a chat's team. The orchestrator can't be deleted.
    func deleteRole(_ roleID: AgentRole.ID, from id: Configuration.ID) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        guard let r = configurations[i].strategy.roles.first(where: { $0.id == roleID }),
              !r.isOrchestrator else { return }
        configurations[i].strategy.roles.removeAll { $0.id == roleID }
        save()
    }

    // MARK: - Saved teams (named presets)

    /// Save a chat's current team as a named, reusable preset in the global library.
    @discardableResult
    func saveTeam(named name: String, from configID: Configuration.ID) -> SavedTeam? {
        guard let config = configurations.first(where: { $0.id == configID }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? strategyDisplayName(config.strategy) : trimmed
        let team = SavedTeam(name: label, strategy: config.strategy)
        savedTeams.insert(team, at: 0)
        save()
        flashSuccess(t("team.saved", label))
        return team
    }

    /// Apply a saved preset to a chat (fresh ids so chats never share role ids).
    func applyTeam(_ team: SavedTeam, to configID: Configuration.ID) {
        guard let i = configurations.firstIndex(where: { $0.id == configID }) else { return }
        let prev = configurations[i].strategy
        let prevAuto = configurations[i].strategyIsAuto
        configurations[i].strategy = team.strategyCopy()
        configurations[i].strategyIsAuto = false   // user chose a team explicitly
        save()
        announceTeamSwap(t("team.applied", team.name),
                         id: configID, previous: prev, previousAuto: prevAuto)
    }

    /// First-message hook: if the chat's team is still "auto", recommend one from the
    /// user's prompt (deterministic AdvisorEngine), apply + persist it, and return it
    /// so the very first turn already uses the recommended team. Returns nil when the
    /// user has already chosen a team (nothing to recommend).
    func autoRecommendStrategyIfNeeded(_ id: Configuration.ID, task: String) async -> Strategy? {
        guard let idx0 = configurations.firstIndex(where: { $0.id == id }),
              configurations[idx0].strategyIsAuto,
              !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // On-device AI reshapes the team when Apple Intelligence is available (free,
        // private); otherwise the deterministic engine. When >1 provider CLI is
        // connected, roles are also mixed across providers (Claude-only otherwise).
        // Re-find the index after the await in case the array changed while thinking.
        let advice = await AdvisorEngine.adviseCrossProvider(task: task, connected: connectedProviders,
                                                             deprioritize: deprioritizedProviders,
                                                             modelLocked: modelLockedProviders)
        Analytics.logRecommendation(advice, task: task, connected: connectedProviders,
                                    deprioritized: deprioritizedProviders)
        guard let i = configurations.firstIndex(where: { $0.id == id }),
              configurations[i].strategyIsAuto else { return nil }
        configurations[i].strategy = advice.strategy
        configurations[i].strategyIsAuto = false
        save()
        flashSuccess(t("chat.autoTeam", strategyDisplayName(advice.strategy)))
        return advice.strategy
    }

    /// B7: start a fresh chat that uses a saved team (the library's fast path).
    /// applyTeam's own flash is the only banner for this action.
    func useTeamInNewChat(_ team: SavedTeam) {
        addConfiguration()
        if let id = selectedConfigID { applyTeam(team, to: id) }
        navSection = .chats
    }

    func renameTeam(_ id: SavedTeam.ID, to name: String) {
        guard let i = savedTeams.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedTeams[i].name = trimmed
        savedTeams[i].updatedAt = Date()
        save()
    }

    func deleteTeam(_ id: SavedTeam.ID) {
        savedTeams.removeAll { $0.id == id }
        if selectedTeamID == id { selectedTeamID = nil }
        save()
    }

    // MARK: Skills ↔ teams

    /// True when the given skill slug is attached to the team.
    func team(_ id: SavedTeam.ID, hasSkill slug: String) -> Bool {
        savedTeams.first { $0.id == id }?.strategy.skills.contains(slug) ?? false
    }

    /// Attach/detach a skill slug to a saved team; the slug is copied into the repo's
    /// .claude/skills (and listed in CLAUDE.md) the next time the team is generated.
    func toggleSkill(_ slug: String, inTeam id: SavedTeam.ID) {
        guard let i = savedTeams.firstIndex(where: { $0.id == id }) else { return }
        if let at = savedTeams[i].strategy.skills.firstIndex(of: slug) {
            savedTeams[i].strategy.skills.remove(at: at)
        } else {
            savedTeams[i].strategy.skills.append(slug)
        }
        savedTeams[i].updatedAt = Date()
        save()
    }

    // MARK: Team-library editing (the Team section works on SavedTeams, not chats)

    /// Create a brand-new team from a strategy template (fresh ids), select it, and
    /// return its id. This is the "create a team" entry point.
    @discardableResult
    func createTeam(from strategy: Strategy, named: String? = nil) -> SavedTeam.ID {
        var s = strategy
        s.id = UUID()
        s.roles = s.roles.map { var r = $0; r.id = UUID(); return r }
        let label = (named?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? strategyDisplayName(strategy)
        let team = SavedTeam(name: label, strategy: s)
        savedTeams.insert(team, at: 0)
        selectedTeamID = team.id
        save()
        flashSuccess(t("team.created", label))
        return team.id
    }

    // MARK: Draft team (configure before committing)

    /// Open a strategy as an in-memory DRAFT team (fresh ids), without saving it. The
    /// Team editor shows it with a "Create team" button; nothing is persisted yet.
    func beginDraftTeam(from strategy: Strategy, named: String? = nil) {
        var s = strategy
        s.id = UUID()
        s.roles = s.roles.map { var r = $0; r.id = UUID(); return r }
        let label = (named?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? strategyDisplayName(strategy)
        selectedTeamID = nil
        draftTeam = SavedTeam(name: label, strategy: s)
    }

    /// Commit the draft into the saved library and select it.
    func commitDraftTeam() {
        guard let draft = draftTeam else { return }
        savedTeams.insert(draft, at: 0)
        selectedTeamID = draft.id
        draftTeam = nil
        save()
        flashSuccess(t("team.created", draft.name))
    }

    /// A binding to the draft team (nil when there's no draft), for the editor.
    var draftTeamBinding: Binding<SavedTeam>? {
        guard draftTeam != nil else { return nil }
        return Binding(
            get: { self.draftTeam ?? SavedTeam(name: "", strategy: StrategyLibrary.solo()) },
            set: { self.draftTeam = $0 }
        )
    }

    /// Run `action`, but if an uncommitted draft team is open, first ask the user to
    /// confirm discarding it. Wrap any "leave the draft" navigation in this.
    func guardedLeave(_ action: @escaping () -> Void) {
        if draftTeam != nil {
            pendingLeave = action
            showDiscardDraftConfirm = true
        } else {
            action()
        }
    }

    /// User confirmed discarding the draft: drop it and run the deferred navigation.
    func confirmDiscardDraft() {
        draftTeam = nil
        showDiscardDraftConfirm = false
        let action = pendingLeave
        pendingLeave = nil
        action?()
    }

    /// User cancelled: keep editing the draft.
    func cancelDiscardDraft() {
        pendingLeave = nil
        showDiscardDraftConfirm = false
    }

    /// A stable two-way binding to a saved team, for the Team editor.
    func teamBinding(_ id: SavedTeam.ID) -> Binding<SavedTeam> {
        Binding(
            get: { self.savedTeams.first(where: { $0.id == id })
                ?? SavedTeam(name: "", strategy: StrategyLibrary.solo()) },
            set: { newValue in
                if let i = self.savedTeams.firstIndex(where: { $0.id == id }) {
                    self.savedTeams[i] = newValue
                }
            }
        )
    }

    /// Add a fresh worker role to a saved team. Returns the new role's id.
    @discardableResult
    func addRole(toTeam id: SavedTeam.ID) -> AgentRole.ID? {
        func makeRole(existingNames: Set<String>) -> AgentRole {
            var name = "agent"; var n = 2
            while existingNames.contains(name) { name = "agent-\(n)"; n += 1 }
            return AgentRole(name: name, role: .worker, model: .sonnet5,
                             systemPrompt: "", description: t("team.newRole.description"), count: 1)
        }
        // Draft team (not yet saved) → mutate the in-memory draft.
        if var draft = draftTeam, draft.id == id {
            let role = makeRole(existingNames: Set(draft.strategy.roles.map(\.name)))
            draft.strategy.roles.append(role)
            draftTeam = draft
            return role.id
        }
        guard let i = savedTeams.firstIndex(where: { $0.id == id }) else { return nil }
        let role = makeRole(existingNames: Set(savedTeams[i].strategy.roles.map(\.name)))
        savedTeams[i].strategy.roles.append(role)
        savedTeams[i].updatedAt = Date()
        save()
        return role.id
    }

    // MARK: Team sharing / importing (marketplace seed — file or copyable text)

    /// Copy a team to the clipboard as a paste-anywhere share string.
    func copyTeamShareText(_ team: SavedTeam) {
        guard let text = try? StrategyPackage.exportText(team.strategy) else {
            show(.failure(t("team.share.failed"))); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Analytics.log(.strategyShared(kind: "text"))
        flashSuccess(t(StrategyPackage.hasRedactableSecrets(team.strategy)
                       ? "team.share.copiedRedacted" : "team.share.copied"))
    }

    /// Export a team to a shareable `.sfstrategy` file.
    func exportTeamDocument(_ team: SavedTeam) {
        exportStrategyFile(team.strategy, logShare: true)
    }

    /// Create a team from a paste-in share string (clipboard).
    func importTeamFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            show(.failure(t("team.import.noText"))); return
        }
        do {
            let strategy = try StrategyPackage.importText(text).autoFixed()
            guard strategy.isValid, !strategy.roles.isEmpty else { show(.failure(t("doc.importInvalid"))); return }
            let id = createTeam(from: strategy, named: strategy.name)
            Analytics.log(.strategyImported(kind: "text"))
            flashSuccess(t("team.import.done"))
            _ = id
        } catch {
            show(.failure(t("doc.importFailed", error.localizedDescription)))
        }
    }

    /// Create a team from a `.sfstrategy` file.
    func importTeamFromFile() {
        guard let url = filePanels.chooseFile(contentTypes: [.sfStrategy], prompt: t("common.choose")) else { return }
        do {
            let strategy = try StrategyPackage.import(Data(contentsOf: url)).autoFixed()
            guard strategy.isValid, !strategy.roles.isEmpty else { show(.failure(t("doc.importInvalid"))); return }
            _ = createTeam(from: strategy, named: strategy.name)
            Analytics.log(.strategyImported(kind: "file"))
            flashSuccess(t("team.import.done"))
        } catch {
            show(.failure(t("doc.importFailed", error.localizedDescription)))
        }
    }

    /// Remove a role from a saved team (the orchestrator can't be deleted).
    func deleteRole(_ roleID: AgentRole.ID, fromTeam id: SavedTeam.ID) {
        // Draft team (not yet saved) → mutate the in-memory draft.
        if var draft = draftTeam, draft.id == id {
            guard let r = draft.strategy.roles.first(where: { $0.id == roleID }), !r.isOrchestrator else { return }
            draft.strategy.roles.removeAll { $0.id == roleID }
            draftTeam = draft
            return
        }
        guard let i = savedTeams.firstIndex(where: { $0.id == id }),
              let r = savedTeams[i].strategy.roles.first(where: { $0.id == roleID }),
              !r.isOrchestrator else { return }
        savedTeams[i].strategy.roles.removeAll { $0.id == roleID }
        savedTeams[i].updatedAt = Date()
        save()
    }

    /// Overwrite an existing preset with a chat's current team.
    func updateTeam(_ id: SavedTeam.ID, from configID: Configuration.ID) {
        guard let ti = savedTeams.firstIndex(where: { $0.id == id }),
              let config = configurations.first(where: { $0.id == configID }) else { return }
        savedTeams[ti].strategy = config.strategy
        savedTeams[ti].updatedAt = Date()
        save()
        flashSuccess(t("team.saved", savedTeams[ti].name))
    }

    /// Set which AI back-end a chat runs on.
    func setProvider(_ id: Configuration.ID, _ provider: AIProvider) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].provider = provider
        save()
    }

    /// Persist a chat's transcript. Device-local, so it does not bump `updatedAt`
    /// or trigger sync (stamp: false).
    func updateTranscript(_ id: Configuration.ID, _ messages: [ChatMessage]) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].transcript = messages
        configurations[i].lastActiveAt = Date()   // bump so active chats rise to the top
        writeTranscript(id, messages)             // the transcript goes to its own sidecar
        saveThrottled()                           // data.json (transcript-free) for metadata
    }

    // MARK: - Coalesced device-local writes
    //
    // During a streamed reply the transcript/usage/draft change many times a second, and
    // each change used to trigger a FULL `save()` (re-encoding every chat's transcript +
    // teams + settings) — ~40 disk encodes/min. Coalesce those hot-path writes into one
    // deferred encode. Safe: the in-memory state updates immediately (nothing is lost from
    // the app's point of view); only the WRITE is delayed ~1s, and `flushSaves()` forces
    // it on background/quit. The format is unchanged, so there is no migration/data risk.
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var pendingSaveSince: Date?

    func saveThrottled() {
        let now = Date()
        if pendingSaveSince == nil { pendingSaveSince = now }
        // Guarantee a write at least every ~3s even under continuous rescheduling (e.g. a
        // non-stop token stream), so a crash can never lose more than that — while still
        // collapsing bursts (typing, per-token usage) into ~one write.
        if now.timeIntervalSince(pendingSaveSince ?? now) > 3.0 {
            pendingSave?.cancel(); pendingSave = nil; pendingSaveSince = nil
            _ = save(stamp: false)
            return
        }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil; self?.pendingSaveSince = nil
            _ = self?.save(stamp: false)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Force any pending coalesced write (data.json AND transcript sidecars) to disk
    /// immediately (call on background/quit).
    /// Deliberately does NOT finalize pending deletes: this fires on ANY leave-foreground
    /// event (hide, minimize, plain deactivation), and finalizing there would silently
    /// void the promised 10s Undo. Pending deletes finalize when their own timer fires,
    /// or on real termination (`finalizeOnTerminate`); until then the on-disk sidecars
    /// are harmless — and load() sweeps tombstoned leftovers if the app dies mid-window.
    func flushSaves() {
        pendingSave?.cancel(); pendingSave = nil; pendingSaveSince = nil
        flushTranscriptWrites()
        // Synchronous: this runs as the app backgrounds/quits, so the write must finish
        // before the process can exit (a detached task might not).
        save(stamp: false, sync: true)
    }

    /// Quit-time cleanup (called from applicationWillTerminate): the undo window dies
    /// with the process, so finalize every pending delete (dangling-link cleanup +
    /// sidecar removal) and force the final synchronous save — the scenePhase flush
    /// alone no longer does this.
    func finalizeOnTerminate() {
        for id in Array(pendingHardDelete.keys) {
            pendingHardDelete[id]?.task.cancel()
            finalizeDelete(id)
        }
        flushSaves()
    }

    /// Write the strategy's `.claude` files into the chat's repo without any UI
    /// banner — so a chat run actually uses the configured team. Idempotent.
    func writeStrategyFilesQuietly(_ id: Configuration.ID) {
        guard let config = configurations.first(where: { $0.id == id }),
              config.strategy.isValid,
              let url = repoURL(for: config) else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try StrategyWriter(repoURL: url, binary: settings.claudeBinary,
                                   memory: memoryDigest(for: config, repoPath: url.path)).write(strategy: config.strategy)
        } catch {
            // Surface the failure (a run against stale/missing team files is a
            // silent misconfiguration) and don't stamp lastGeneratedAt.
            flashFailure(t("chat.teamFilesFailed", error.localizedDescription))
            return
        }
        if let i = configurations.firstIndex(where: { $0.id == id }) {
            configurations[i].lastGeneratedAt = Date()
            save(stamp: false)
        }
    }

    /// Persist a chat's unsent draft. Device-local; coalesced so typing doesn't trigger a
    /// full state encode on every keystroke (a losable, non-critical draft).
    func updateDraft(_ id: Configuration.ID, _ text: String) {
        guard let i = configurations.firstIndex(where: { $0.id == id }),
              configurations[i].draft != text else { return }
        configurations[i].draft = text
        saveThrottled()
    }

    /// Persist a chat's cumulative token/cost usage. Device-local (stamp: false).
    /// Coalesced: usage updates fire per token/worker; the counter is non-critical (it's
    /// re-derivable), so a deferred write is safe and avoids a full encode per token.
    func updateUsage(_ id: Configuration.ID, tokens: Int, costUSD: Double) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].totalTokens = tokens
        configurations[i].totalCostUSD = costUSD
        saveThrottled()
    }

    // MARK: - Transcript sidecars (device-local, per-chat)
    //
    // A chat's transcript can be large and grows every token; keeping it inline in
    // data.json meant every save re-encoded EVERY chat's full history. Transcripts now
    // live in a per-chat sidecar (transcripts/<id>.json): data.json is encoded WITHOUT
    // them (small + fast), and only the active chat's sidecar is rewritten as it streams.
    // Backward compatible: an old data.json with inline transcripts still loads, and its
    // transcript is migrated to a sidecar on load (synchronously, before any save can
    // strip it) so nothing is ever lost.

    private func transcriptURL(_ id: Configuration.ID) -> URL {
        let dir = storeDirectory.appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Coalesces + orders the per-chat sidecar writes, mirroring save()'s pattern:
    /// a superseded snapshot's detached write must never land after a newer one.
    @ObservationIgnored private var transcriptWriteTasks: [Configuration.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var transcriptSerializers: [Configuration.ID: SaveSerializer] = [:]
    @ObservationIgnored private var transcriptGenerations: [Configuration.ID: UInt64] = [:]

    /// Write one chat's transcript to its sidecar, atomically. The encode + write run
    /// OFF the main actor (a streaming flush re-encodes the FULL transcript, which
    /// grows without bound — done synchronously it was a recurring main-thread stall
    /// on long chats), ordered per chat through a SaveSerializer so a stale snapshot
    /// can never overwrite a newer one. `sync: true` writes on THIS thread instead:
    /// load()'s inline → sidecar migration needs the sidecar to exist before any
    /// save() strips the inline copy, and flushSaves() must finish before quit.
    private func writeTranscript(_ id: Configuration.ID, _ messages: [ChatMessage], sync: Bool = false) {
        guard !unhydratedTranscriptIDs.contains(id) else {
            // A not-yet-hydrated chat must never persist: its in-memory transcript is
            // a placeholder, and writing it (worst case an empty array) would clobber
            // the real history still sitting in the sidecar.
            DiagnosticsLog.record("Dropped transcript write for un-hydrated chat \(id)")
            return
        }
        let url = transcriptURL(id)
        let serializer: SaveSerializer
        if let existing = transcriptSerializers[id] {
            serializer = existing
        } else {
            serializer = SaveSerializer()
            transcriptSerializers[id] = serializer
        }
        let generation = (transcriptGenerations[id] ?? 0) + 1
        transcriptGenerations[id] = generation
        transcriptWriteTasks[id]?.cancel()
        if sync {
            transcriptWriteTasks[id] = nil
            do { try serializer.write(JSONEncoder().encode(messages), to: url, generation: generation) }
            catch { DiagnosticsLog.record("Couldn't write transcript sidecar for \(id): \(error.localizedDescription)") }
            return
        }
        transcriptWriteTasks[id] = Task.detached(priority: .utility) { [serializer] in
            do {
                let data = try JSONEncoder().encode(messages)
                guard !Task.isCancelled else { return }
                try serializer.write(data, to: url, generation: generation)
            } catch {
                // Streaming hot path — never surface a banner, but don't lose the failure
                // silently either (a full disk / permission issue is otherwise invisible).
                DiagnosticsLog.record("Couldn't write transcript sidecar for \(id): \(error.localizedDescription)")
            }
        }
    }

    /// Force any in-flight coalesced transcript writes to disk on THIS thread (part
    /// of flushSaves): each pending chat's current in-memory transcript is rewritten
    /// at a fresh generation, so a straggling detached write is dropped by its
    /// serializer instead of landing stale after the flush.
    private func flushTranscriptWrites() {
        for id in Array(transcriptWriteTasks.keys) {
            transcriptWriteTasks[id]?.cancel()
            transcriptWriteTasks[id] = nil
            // A soft-deleted chat inside its undo window is gone from `configurations`
            // but its sidecar is intentionally kept — land the last write from the
            // undo copy, or an Undo would restore a truncated transcript.
            guard let messages = configurations.first(where: { $0.id == id })?.transcript
                    ?? pendingHardDelete[id]?.config.transcript else { continue }
            writeTranscript(id, messages, sync: true)
        }
    }

    /// Cancel + invalidate any in-flight transcript write for a chat whose sidecar is
    /// about to be deleted: a detached write past its cancellation check would
    /// otherwise re-create the file after removal. The barrier marks every issued
    /// generation as written, so the serializer drops the straggler.
    private func discardPendingTranscriptWrites(_ id: Configuration.ID) {
        transcriptWriteTasks[id]?.cancel()
        transcriptWriteTasks[id] = nil
        transcriptSerializers[id]?.barrier(upTo: transcriptGenerations[id] ?? 0)
    }

    private func loadTranscript(_ id: Configuration.ID) -> [ChatMessage]? {
        let url = transcriptURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }   // no file = normal
        if let msgs = Self.decodeMessagesTolerantly(data) { return msgs }
        // The file exists but can't be parsed at all. Back it up BEFORE returning nil —
        // otherwise the next writeTranscript would overwrite (destroy) recoverable history.
        backupCorruptSidecar(url, kind: "transcript")
        return nil
    }

    // MARK: Lazy transcript hydration
    //
    // Launch used to read + JSON-decode EVERY chat's sidecar synchronously before the
    // first frame — O(total chat history) on the main actor. Now load() eagerly hydrates
    // only what the first frame needs (the restored selection, plus legacy inline
    // migrations); everything else hydrates in a background task, or on demand the
    // moment an action touches it. The set below is the arbiter: while an id is in it,
    // the chat's in-memory transcript is a placeholder and must be neither trusted nor
    // persisted (writeTranscript drops writes for un-hydrated ids).

    /// Chats whose transcripts have NOT been hydrated from their sidecars yet. Every
    /// path that reads or rewrites a transcript hydrates first (selection, delete,
    /// duplicate); sidebar previews/deep search just re-render when hydration lands.
    @ObservationIgnored private var unhydratedTranscriptIDs: Set<Configuration.ID> = []

    /// Bumped (observable) each time hydration lands transcripts, so an active
    /// sidebar deep search — which snapshots transcripts once per query — can
    /// re-run over the now-complete histories instead of keeping a stale miss.
    private(set) var transcriptHydrationGeneration = 0

    /// Synchronously hydrate one chat's transcript if the background task hasn't
    /// reached it yet — the on-demand path for a chat touched right after launch.
    /// ACTION context only: it mutates observed state (never call from a view body).
    private func hydrateTranscriptIfNeeded(_ id: Configuration.ID) {
        guard unhydratedTranscriptIDs.remove(id) != nil else { return }
        guard let i = configurations.firstIndex(where: { $0.id == id }),
              configurations[i].transcript.isEmpty,
              let t = loadTranscript(id) else { return }
        configurations[i].transcript = t
        transcriptHydrationGeneration += 1
    }

    /// Read + decode every remaining chat's sidecar OFF the main actor, then land the
    /// results back on it. Runs once, at the end of load(). Legacy auto-title
    /// upgrading needs the transcripts, so it waits until hydration completes.
    private func hydrateRemainingTranscripts() {
        guard !unhydratedTranscriptIDs.isEmpty else {
            retitleAutoNamedChats()   // upgrade legacy auto-titles in place (idempotent)
            return
        }
        let jobs = unhydratedTranscriptIDs.map { ($0, transcriptURL($0)) }
        Task.detached(priority: .utility) { [weak self] in
            var loaded: [(Configuration.ID, [ChatMessage])] = []
            var corrupt: [Configuration.ID] = []
            for (id, url) in jobs {
                guard let data = try? Data(contentsOf: url) else { continue }   // no file = normal
                if let msgs = AppModel.decodeMessagesTolerantly(data) { loaded.append((id, msgs)) }
                else { corrupt.append(id) }
            }
            let found = loaded
            let bad = corrupt
            await MainActor.run { self?.applyHydratedTranscripts(found, corrupt: bad) }
        }
    }

    /// Land the background-hydrated transcripts (main actor). Skips any chat that was
    /// hydrated on demand — or deleted — while the reads ran; the un-hydrated set is
    /// the arbiter, so a stale read can never overwrite live state.
    private func applyHydratedTranscripts(_ loaded: [(Configuration.ID, [ChatMessage])],
                                          corrupt: [Configuration.ID]) {
        for (id, messages) in loaded {
            guard unhydratedTranscriptIDs.contains(id),
                  let i = configurations.firstIndex(where: { $0.id == id }),
                  configurations[i].transcript.isEmpty else { continue }
            configurations[i].transcript = messages
        }
        for id in corrupt where unhydratedTranscriptIDs.contains(id) {
            // Unreadable sidecar → park it (mirrors loadTranscript) so a later write
            // can't destroy recoverable history.
            backupCorruptSidecar(transcriptURL(id), kind: "transcript")
        }
        unhydratedTranscriptIDs.removeAll()
        transcriptHydrationGeneration += 1
        retitleAutoNamedChats()   // upgrade legacy auto-titles in place (idempotent)
    }

    /// Decode a transcript, dropping any single malformed message instead of losing the
    /// whole history. Returns nil only when the data isn't a decodable array at all.
    nonisolated static func decodeMessagesTolerantly(_ data: Data) -> [ChatMessage]? {
        let dec = JSONDecoder()
        if let msgs = try? dec.decode([ChatMessage].self, from: data) { return msgs }
        struct Lossy: Decodable {
            let messages: [ChatMessage]
            struct Skip: Decodable { init(from decoder: Decoder) throws {} }
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                var out: [ChatMessage] = []
                while !c.isAtEnd {
                    if let m = try? c.decode(ChatMessage.self) { out.append(m) }
                    else { _ = try? c.decode(Skip.self) }   // advance past the bad element
                }
                messages = out
            }
        }
        return (try? dec.decode(Lossy.self, from: data))?.messages
    }

    /// Move an unreadable sidecar aside (never delete it) so it's recoverable, and log
    /// where it went — mirrors the corrupt-data.json handling in load().
    private func backupCorruptSidecar(_ url: URL, kind: String) {
        let stamp = String(Int(Date().timeIntervalSince1970))
        let dest = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: dest)
        DiagnosticsLog.record("Unreadable \(kind) sidecar parked at \(dest.lastPathComponent)")
    }

    // MARK: - Agent activity history (device-local, per-chat sidecar — never synced)

    private func activityURL(_ id: Configuration.ID) -> URL {
        let dir = storeDirectory.appendingPathComponent("activity", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    /// The persisted turn-by-turn agent history for a chat (empty if none).
    func loadActivity(_ id: Configuration.ID) -> [TurnActivity] {
        let url = activityURL(id)
        guard let data = try? Data(contentsOf: url) else { return [] }   // no file = normal
        if let turns = try? JSONDecoder().decode([TurnActivity].self, from: data) { return turns }
        // Unreadable → park it (don't let the next append destroy it) and start fresh.
        backupCorruptSidecar(url, kind: "activity")
        return []
    }

    /// Append one finished turn, capped to the last 50, written atomically. Does NOT
    /// touch data.json / save() — no sync, no mid-stream store rewrites.
    func appendActivity(_ id: Configuration.ID, _ turn: TurnActivity) {
        var all = loadActivity(id)
        all.append(turn)
        if all.count > 50 { all = Array(all.suffix(50)) }
        do {
            let data = try JSONEncoder().encode(all)
            try data.write(to: activityURL(id), options: .atomic)
        } catch {
            DiagnosticsLog.record("Couldn't write activity sidecar for \(id): \(error.localizedDescription)")
        }
    }

    // MARK: - Chat view-model lookup

    /// The (cached) view model for a chat. Creates it on first use and keeps it
    /// alive across navigation, so a running turn keeps streaming off-screen.
    /// Safe to call from a view body: it only touches @ObservationIgnored storage
    /// and refreshes the VM's (unobserved-by-callers) config snapshot.
    /// Keyboard chat switcher (⌥⌘↑ / ⌥⌘↓): move the selection to the previous/next chat
    /// in the sidebar's own newest-first order. Clamps at the ends (no wrap) and routes
    /// through guardedLeave so an unsaved team draft still warns. Jumps back to the chat
    /// list if the user is elsewhere.
    func selectAdjacentChat(_ delta: Int) {
        let ordered = configurations.sorted { $0.recency > $1.recency }
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedConfigID }
        // From outside the list (no selection), ↓ starts at the top, ↑ at the bottom.
        let target: Int
        if let c = current {
            target = min(max(c + delta, 0), ordered.count - 1)
        } else {
            target = delta > 0 ? 0 : ordered.count - 1
        }
        let id = ordered[target].id
        guardedLeave { [weak self] in
            self?.navSection = .chats
            self?.selectedConfigID = id
        }
    }

    /// Stop the selected chat's live turn from the menu (⌘.). Touches only an already
    /// built VM — never instantiates one just to ask it to stop.
    func stopSelectedChat() {
        guard let id = selectedConfigID, let vm = chatVMs[id], vm.isRunning else { return }
        vm.stop()
    }

    func chatViewModel(for id: Configuration.ID) -> ChatViewModel? {
        guard let config = configurations.first(where: { $0.id == id }) else { return nil }
        if let vm = chatVMs[id] {
            // Refresh on lookup, but ONLY when it actually changed: vm.config is
            // observed (AgentActivityPanel/CodeModeView read it in their bodies),
            // so an unconditional write here would mutate observed state on every
            // ContentView body evaluation — the mutate-during-render hazard.
            if vm.config != config { vm.config = config }
            return vm
        }
        let vm = ChatViewModel(
            config: config,
            binary: settings.claudeBinary,
            providerBinaries: providerBinaries,
            providerAPIKeys: providerAPIKeys(),
            codexReasoningEffort: settings.codexReasoningEffort,
            permissionMode: settings.chatAutonomy.permissionMode,
            // Read the infra settings FRESH each turn so changing a CLI path / API key /
            // Codex effort in Settings reaches this already-open (cached) chat.
            liveSettings: { [weak self] in
                guard let self else {
                    return ChatRunSettings(claudeBinary: "claude", providerBinaries: [:],
                                           providerAPIKeys: [:], codexReasoningEffort: "")
                }
                return ChatRunSettings(
                    claudeBinary: self.settings.claudeBinary,
                    providerBinaries: self.providerBinaries,
                    providerAPIKeys: self.providerAPIKeys(),
                    codexReasoningEffort: self.settings.codexReasoningEffort)
            },
            persist: { [weak self] messages in self?.updateTranscript(id, messages) },
            onFirstUserMessage: { [weak self] text in self?.autoTitleIfNeeded(id, fromFirstMessage: text) },
            autoRecommendStrategy: { [weak self] text in
                guard let self else { return nil }
                return await self.autoRecommendStrategyIfNeeded(id, task: text)
            },
            ensureStrategyFiles: { [weak self] in self?.writeStrategyFilesQuietly(id) },
            persistUsage: { [weak self] tokens, cost in self?.updateUsage(id, tokens: tokens, costUSD: cost) },
            persistActivity: { [weak self] turn in self?.appendActivity(id, turn) },
            initialHistory: loadActivity(id))
        vm.onRunningChanged = { [weak self, weak vm] running in
            guard let self else { return }
            if running {
                self.runningChatIDs.insert(id)
            } else {
                self.runningChatIDs.remove(id)
                let elsewhere = self.navSection != .chats || self.selectedConfigID != id
                let needsPermission = !(vm?.deniedTools.isEmpty ?? true)
                // Finish banner only when the user is somewhere else.
                if elsewhere {
                    let name = self.configurations.first(where: { $0.id == id })?.name ?? ""
                    let display = name.isEmpty ? self.t("chat.untitled") : name
                    if vm?.errorText != nil {
                        self.flashFailure(self.t("chat.turnFailed", display))
                    } else {
                        self.flashSuccess(self.t("chat.turnDone", display))
                    }
                }
                // Bounce the Dock + flag the chat when the user isn't watching (or a
                // permission decision is now pending — that keeps bouncing).
                if elsewhere || needsPermission || !NSApp.isActive {
                    self.flagAttention(id, critical: needsPermission)
                }
            }
        }
        chatVMs[id] = vm
        return vm
    }

    /// Drop a chat's cached VM (stops any in-flight run). Call after the chat's
    /// repo binding changes or before deleting the chat — NEVER from a view body.
    func invalidateChatVM(_ id: Configuration.ID) {
        if let vm = chatVMs[id] {
            // Detach the running-state callback first: stop() flips isRunning,
            // and the callback would otherwise flash a spurious "turn done"
            // banner for a chat that is being deleted or re-bound.
            vm.onRunningChanged = nil
            vm.stop()
        }
        chatVMs[id] = nil
        runningChatIDs.remove(id)
    }

    /// Keep memory light: release the ChatViewModels of chats that are neither RUNNING nor
    /// among the few most-recently-used (so their transcript/history/provenance stop being
    /// resident). Without this, every chat opened in a session stayed fully in RAM forever —
    /// the classic "slowly eats memory" profile. Called from selection actions ONLY (never a
    /// view body): `invalidateChatVM` mutates the cache + tears the VM down safely.
    func evictIdleChatVMs(keepingRecent keep: Int = 3) {
        if let sel = selectedConfigID {
            recentChatIDs.removeAll { $0 == sel }
            recentChatIDs.insert(sel, at: 0)
            if recentChatIDs.count > keep { recentChatIDs.removeLast(recentChatIDs.count - keep) }
        }
        // Never evict a chat with a live turn, the current selection, or an MRU chat.
        var survivors = Set(recentChatIDs).union(runningChatIDs)
        if let sel = selectedConfigID { survivors.insert(sel) }
        for id in chatVMs.keys where !survivors.contains(id) {
            invalidateChatVM(id)
        }
    }

    // MARK: - Code section (repo-first, single-agent Claude)

    /// Create a single-agent (solo Claude) chat bound to `repoURL` and open it in
    /// Code Mode. This is the repo-first "door" — no team design, straight to work.
    func openCodeChat(repoURL: URL) {
        let bookmark = try? repoURL.bookmarkData(options: [.withSecurityScope],
                                                 includingResourceValuesForKeys: nil, relativeTo: nil)
        var config = Configuration(
            name: repoURL.lastPathComponent,
            strategy: StrategyLibrary.solo(),
            repoPath: repoURL.path,
            repoBookmark: bookmark,
            lastActiveAt: Date(),
            titleWasManuallySet: true
        )
        config.strategyIsAuto = false
        configurations.append(config)
        selectedConfigID = config.id
        liveRepoURLs[config.id] = repoURL
        openInCodeMode = config.id
        UserDefaults.standard.set(repoURL.path, forKey: "code.lastRepo")
        recordRecentRepo(repoURL.path)
        navSection = .chats
        save()
    }

    /// Push a repo path onto the recent-repos list (newest first, deduped, capped).
    func recordRecentRepo(_ path: String) {
        var list = (UserDefaults.standard.array(forKey: "code.recentRepos") as? [String]) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: "code.recentRepos")
    }

    /// Recently opened repos that still exist on disk (for the Code launcher list).
    var recentRepoPaths: [String] {
        let list = (UserDefaults.standard.array(forKey: "code.recentRepos") as? [String]) ?? []
        var seen = Set<String>()
        return list.filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
    }

    /// Session cache of the user's GitHub repos, so entering Code doesn't re-run `gh` every
    /// time (a slow subprocess that made the section switch feel laggy). Refreshed only when
    /// empty or stale; survives view recreation because it lives on the model, not @State.
    var cachedGitHubRepos: [GitHubCLI.RepoRef] = []
    @ObservationIgnored var gitHubReposLoadedAt: Date?

    /// Create a brand-new GitHub repo and open it in Code Mode — no trip to
    /// github.com and back.
    func createAndOpenGitHubRepo(name: String, isPrivate: Bool) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parent = resolvedDefaultReposURL()?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Coral")
        let r = await GitHubCLI.createRepo(name: trimmed, isPrivate: isPrivate, into: parent)
        guard r.ok, let path = r.path else { flashFailure(t("code.createRepoFailed")); return }
        openCodeChat(repoURL: URL(fileURLWithPath: path))
        flashSuccess(t("code.repoCreated", (path as NSString).lastPathComponent))
    }

    /// Clone `url` into the default repos folder, then open it in Code Mode.
    func cloneAndOpenCodeChat(url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parent = resolvedDefaultReposURL()?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Coral")
        let r = await CodeGit.clone(url: trimmed, into: parent)
        guard r.ok, let path = r.path else { flashFailure(t("code.cloneFailed")); return }
        openCodeChat(repoURL: URL(fileURLWithPath: path))
        flashSuccess(t("code.cloned", (path as NSString).lastPathComponent))
    }

    /// Pick a local folder and open it in Code Mode.
    func pickAndOpenCodeChat() {
        guard let url = filePanels.chooseDirectory(prompt: t("repo.picker.prompt"), message: nil,
                                                   startingAt: resolvedDefaultReposURL()) else { return }
        openCodeChat(repoURL: url)
    }

    // MARK: - Repo selection

    /// Present an open panel to choose the target repo folder for a configuration.
    /// Returns true iff the user actually picked a folder.
    @discardableResult
    func pickRepo(for id: Configuration.ID) -> Bool {
        guard let url = filePanels.chooseDirectory(prompt: t("repo.picker.prompt"),
                                                   message: t("repo.picker.message"),
                                                   startingAt: resolvedDefaultReposURL()),
              let i = configurations.firstIndex(where: { $0.id == id }) else { return false }

        configurations[i].repoPath = url.path
        configurations[i].repoBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        liveRepoURLs[id] = url
        save()
        Analytics.log(.repoSelected(sample: false))
        // The chat VM caches the repo path at construction — rebuild it.
        invalidateChatVM(id)
        if configurations[i].repoBookmark == nil {
            flashFailure(t("banner.repoBookmarkFailed"))
        } else {
            flashSuccess(t("banner.repoBound", url.lastPathComponent))
        }
        return true
    }

    /// Present an open panel to choose the default repos folder (Settings).
    func pickDefaultReposFolder() {
        guard let url = filePanels.chooseDirectory(prompt: t("repo.picker.prompt"), message: nil,
                                                   startingAt: nil) else { return }
        settings.defaultReposPath = url.path
        settings.defaultReposBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        save()
    }

    // MARK: - URL resolution

    /// The repo URL for a configuration: a live picked URL, else a resolved
    /// bookmark, else the raw path.
    func repoURL(for config: Configuration) -> URL? {
        if let live = liveRepoURLs[config.id] { return live }
        if let data = config.repoBookmark, let res = SecurityScopedBookmark.resolve(data) {
            liveRepoURLs[config.id] = res.url
            // A stale bookmark was regenerated — persist the fresh data OUT of this render
            // pass (repoURL runs inside view bodies; mutating + saving here would be a
            // mid-render observed-state write).
            if let fresh = res.refreshedData {
                let id = config.id
                Task { @MainActor in self.persistRefreshedBookmark(fresh, forConfig: id) }
            }
            return res.url
        }
        if let path = config.repoPath { return URL(fileURLWithPath: path) }
        return nil
    }

    /// Store a regenerated security-scoped bookmark for a config and persist it.
    private func persistRefreshedBookmark(_ data: Data, forConfig id: Configuration.ID) {
        guard let i = configurations.firstIndex(where: { $0.id == id }),
              configurations[i].repoBookmark != data else { return }
        configurations[i].repoBookmark = data
        save(stamp: false)   // device-local binding refresh, not a content edit
    }

    private func resolvedDefaultReposURL() -> URL? {
        if let data = settings.defaultReposBookmark, let res = SecurityScopedBookmark.resolve(data) {
            if let fresh = res.refreshedData, settings.defaultReposBookmark != fresh {
                settings.defaultReposBookmark = fresh
                save(stamp: false)
            }
            return res.url
        }
        if let path = settings.defaultReposPath { return URL(fileURLWithPath: path) }
        return nil
    }

    // MARK: - Preview

    /// The cross-project learnings block (MemoryDigest) to inject into a config's
    /// generated CLAUDE.md, selected for its repo + task context. Empty when nothing in
    /// the knowledge base is relevant, which keeps the generated file identical to before.
    func memoryDigest(for config: Configuration, repoPath: String?) -> String {
        let ctx = MemoryContext(repoPath: repoPath, language: nil, taskText: config.name)
        let picked = MemorySelector.topN(MemoryStore.shared.learnings, context: ctx, limit: 6)
        return MemoryDigest.render(picked)
    }

    /// Files that would be written for a configuration, merged against disk.
    func previewFiles(for config: Configuration) -> [GeneratedFile] {
        if let url = repoURL(for: config) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return StrategyWriter(repoURL: url, binary: settings.claudeBinary,
                                  memory: memoryDigest(for: config, repoPath: url.path))
                .previewFiles(for: config.strategy)
        }
        // No repo yet: still preview agent files + a from-scratch CLAUDE.md.
        var files = AgentFileGenerator.generate(for: config.strategy)
        let claude = ClaudeMdGenerator.merged(existing: nil, strategy: config.strategy,
                                              binary: settings.claudeBinary,
                                              memory: memoryDigest(for: config, repoPath: nil))
        files.append(GeneratedFile(relativePath: ClaudeMdGenerator.fileName, contents: claude))
        return files
    }

    /// A pre-write diff of every file that would be written — what changes on disk
    /// before anything is written. When no repo is chosen yet, everything is "created".
    func previewDiffs(for config: Configuration) -> [FileDiff] {
        if let url = repoURL(for: config) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return StrategyWriter(repoURL: url, binary: settings.claudeBinary,
                                  memory: memoryDigest(for: config, repoPath: url.path))
                .previewDiffs(for: config.strategy)
        }
        return previewFiles(for: config).map { FileDiff.make(file: $0, existing: nil) }
    }

    func launchCommand(for config: Configuration) -> String {
        LaunchCommandGenerator.command(for: config.strategy, binary: settings.claudeBinary)
    }

    /// Relative paths of agent files that already exist and would be overwritten.
    func overwriteConflicts(for config: Configuration) -> [String] {
        guard let url = repoURL(for: config) else { return [] }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return StrategyWriter(repoURL: url, binary: settings.claudeBinary)
            .existingAgentConflicts(for: config.strategy)
    }

    // MARK: - Generation actions

    /// Write the configuration's files to disk. Returns true on success.
    @discardableResult
    func generate(_ config: Configuration) -> Bool {
        guard config.strategy.isValid else {
            show(.failure(t("banner.needValid")))
            return false
        }
        guard let url = repoURL(for: config) else {
            show(.failure(t("banner.needRepo")))
            return false
        }
        // Never write into the home folder: `.claude/agents/*` there become GLOBAL
        // subagents for every project on the machine — almost never intended.
        if url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            show(.failure(t("banner.generateHome")))
            return false
        }
        let isGitRepo = FileManager.default.fileExists(
            atPath: url.appendingPathComponent(".git").path)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let writer = StrategyWriter(repoURL: url, binary: settings.claudeBinary,
                                        memory: memoryDigest(for: config, repoPath: url.path))
            // Classify what's about to change (before the write) for the funnel.
            let diffs = writer.previewDiffs(for: config.strategy)
            let written = try writer.write(strategy: config.strategy)
            if let i = configurations.firstIndex(where: { $0.id == config.id }) {
                configurations[i].lastGeneratedAt = Date()
                save()
            }
            // The activation aha — .claude/agents + CLAUDE.md written into a repo.
            Analytics.log(.filesGenerated(provider: config.provider.rawValue,
                                          agents: config.strategy.roles.count))
            Analytics.log(.diffApplied(created: diffs.filter { $0.change == .created }.count,
                                       modified: diffs.filter { $0.change == .modified }.count,
                                       deleted: diffs.filter { $0.change == .deleted }.count))
            // Not a git repo → the generated config won't be versioned (and can't be
            // shared/committed). Say so, but still generate — it's a valid local setup.
            show(.success(t(isGitRepo ? "banner.wrote" : "banner.wroteNoGit",
                            written.count, url.lastPathComponent)))
            return true
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
            return false
        }
    }

    /// Write files, copy the launch command to the clipboard, and open Terminal at
    /// the repo folder. Terminal automation is not available in the sandbox, so the
    /// command is delivered via the clipboard for the user to paste.
    func generateAndOpenTerminal(_ config: Configuration) {
        guard generate(config), let url = repoURL(for: config) else { return }
        openTerminal(at: url, running: launchCommand(for: config))
    }

    /// Write files, then open Terminal at the repo with a `git add/commit` for the
    /// generated config copied to the clipboard — so the team-shared setup is
    /// versioned with the repo. (Sandbox can't run git directly, so we prepare the
    /// command like the launch command.)
    func generateAndCommit(_ config: Configuration) {
        guard generate(config), let url = repoURL(for: config) else { return }
        openTerminal(at: url, running: LaunchCommandGenerator.gitCommitCommand())
    }

    /// Run `cd <folder> && <command>` in Terminal — for real. We write a temporary
    /// executable `.command` script and open it; macOS runs `.command` files in
    /// Terminal, so the command actually EXECUTES (no clipboard paste needed) while
    /// staying inside the sandbox (we only write a temp file and `open` it).
    private func openTerminal(at url: URL, running command: String) {
        let script = """
        #!/bin/zsh
        cd \(shellQuoted(url.path)) || exit 1
        \(command)
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Coral-\(UUID().uuidString).command")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            if NSWorkspace.shared.open(scriptURL) {
                show(.success(t("banner.terminalRunning")))
                return
            }
        } catch {
            // fall through to the clipboard fallback
        }
        // Fallback: copy the command and open the folder in Terminal to paste.
        let full = "cd \(shellQuoted(url.path)) && \(command)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                self.show(error == nil ? .success(self.t("banner.terminalCopied"))
                                       : .failure(self.t("banner.terminalFailed")))
            }
        }
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Beginner actions

    /// Save the strategy as a single self-contained `.md` the user can drag into a
    /// Claude chat (no repo/Terminal needed).
    func downloadBrief(_ config: Configuration) {
        guard let url = filePanels.save(suggestedName: StandaloneBriefGenerator.fileName(for: config.strategy),
                                        contentTypes: [UTType(filenameExtension: "md") ?? .plainText]) else { return }
        do {
            try StandaloneBriefGenerator.brief(for: config.strategy)
                .write(to: url, atomically: true, encoding: .utf8)
            show(.success(t("banner.downloaded")))
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
        }
    }

    /// Reveal the generated `.claude` files (or the repo) in Finder.
    func revealGeneratedFiles(_ config: Configuration) {
        guard let url = repoURL(for: config) else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let claude = url.appendingPathComponent(".claude", isDirectory: true)
        let target = FileManager.default.fileExists(atPath: claude.path) ? claude : url
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// Copy a short starter prompt the user can paste into a Claude chat.
    func copyStarterPrompt(_ config: Configuration) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(StandaloneBriefGenerator.starterPrompt(for: config.strategy), forType: .string)
        flashSuccess(t("banner.promptCopied"))
    }

    /// One-click beginner setup: create a proven default config and immediately ask
    /// for the target folder (the one unavoidable decision).
    func setUpForMe() {
        let config = Configuration(name: t("setup.defaultName"),
                                   strategy: StrategyLibrary.executorAdvisor(),
                                   titleWasManuallySet: true)
        configurations.append(config)
        selectedConfigID = config.id
        save()
        if !pickRepo(for: config.id) {
            // No folder yet is fine — the chat still works in a scratch folder.
            flashSuccess(t("setup.noFolderYet"))
        }
    }

    /// Create a throwaway practice folder (user picks where) with a starter file,
    /// so a beginner can experiment end-to-end with zero risk.
    func trySampleFolder() {
        guard let parent = filePanels.chooseDirectory(prompt: t("common.choose"),
                                                      message: t("setup.sample.sub"),
                                                      startingAt: nil) else { return }

        let didAccess = parent.startAccessingSecurityScopedResource()
        defer { if didAccess { parent.stopAccessingSecurityScopedResource() } }
        let sample = parent.appendingPathComponent("Coral Sandbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
            try "# Practice project\n\nMade by Coral. Ask Claude to add a file here — you can delete this whole folder anytime.\n"
                .write(to: sample.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            let bookmark = try? sample.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
            let config = Configuration(name: t("setup.defaultName"),
                                       strategy: StrategyLibrary.executorAdvisor(),
                                       repoPath: sample.path, repoBookmark: bookmark,
                                       titleWasManuallySet: true)
            configurations.append(config)
            selectedConfigID = config.id
            liveRepoURLs[config.id] = sample
            save()
            flashSuccess(t("banner.saved"))
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
        }
    }

    // MARK: - Persistence (JSON in Application Support)

    struct PersistedState: Codable {
        /// Current on-disk schema. Pre-versioned files decode as version 0 and are
        /// migrated forward on load.
        static let currentVersion = 1

        var schemaVersion: Int
        var configurations: [Configuration]
        var settings: AppSettings
        var savedTeams: [SavedTeam]
        /// Tombstones: ids of chats deleted locally, so sync can remove them from iCloud
        /// AND stop the remote copy from resurrecting them on the next merge.
        var deletedConfigIDs: [UUID]
        /// Per-config `updatedAt` at the last successful sync (see AppModel.syncBaseline),
        /// so conflict detection survives a relaunch.
        var syncBaseline: [String: Date]

        init(configurations: [Configuration],
             settings: AppSettings,
             savedTeams: [SavedTeam] = [],
             deletedConfigIDs: [UUID] = [],
             syncBaseline: [String: Date] = [:],
             schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.configurations = configurations
            self.settings = settings
            self.savedTeams = savedTeams
            self.deletedConfigIDs = deletedConfigIDs
            self.syncBaseline = syncBaseline
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, configurations, settings, savedTeams, deletedConfigIDs, syncBaseline }

        // Tolerant decode: older files have no schemaVersion (→ 0). Missing
        // settings/savedTeams default rather than failing the whole load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            // Lossy per-element: ONE corrupt chat/team must not fail the whole decode and
            // empty the library — drop the bad element, keep the rest.
            configurations = Self.lossyArray(Configuration.self, from: c, forKey: .configurations)
            settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
            savedTeams = Self.lossyArray(SavedTeam.self, from: c, forKey: .savedTeams)
            deletedConfigIDs = try c.decodeIfPresent([UUID].self, forKey: .deletedConfigIDs) ?? []
            syncBaseline = (try? c.decodeIfPresent([String: Date].self, forKey: .syncBaseline) ?? [:]) ?? [:]
        }

        /// Decode an array dropping any single malformed element, so a corrupt entry
        /// never fails the whole store decode. Absent key → empty.
        static func lossyArray<T: Decodable>(_ type: T.Type, from c: KeyedDecodingContainer<CodingKeys>,
                                             forKey key: CodingKeys) -> [T] {
            if let all = try? c.decodeIfPresent([T].self, forKey: key) { return all ?? [] }
            guard var u = try? c.nestedUnkeyedContainer(forKey: key) else { return [] }
            var out: [T] = []
            while !u.isAtEnd {
                if let v = try? u.decode(T.self) { out.append(v) } else { _ = try? u.decode(DecoderSkip.self) }
            }
            return out
        }

        /// Forward-migrate a decoded state to the current schema version.
        func migrated() -> PersistedState {
            // v0 → v1: no field changes (versioning introduced); accept as-is.
            var s = self
            s.schemaVersion = PersistedState.currentVersion
            return s
        }
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("data.json")
    }

    /// Coalesces rapid saves; a new save supersedes an in-flight write.
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    /// Orders data.json writes across the detached save tasks and the final sync write,
    /// so a stale snapshot can never land after — and overwrite — a newer one.
    @ObservationIgnored private let saveSerializer = SaveSerializer()
    /// Monotonic id for each save; bumped on the main actor, so later saves always
    /// carry a higher generation than the writes they supersede.
    @ObservationIgnored private var saveGeneration: UInt64 = 0

    /// Persist the store. Encoding + disk I/O run OFF the main actor and are
    /// coalesced, so streaming a reply (which saves on every chunk) never blocks the
    /// UI re-writing the whole store synchronously. Returns optimistically; a write
    /// failure surfaces as a banner.
    @discardableResult
    func save(stamp: Bool = true, sync: Bool = false) -> Bool {
        // `snapshotConfigurations` only feeds `stampChanges`' next diff, so it's needed
        // only when stamping. Keeping it off the streaming persist path (stamp:false,
        // fired every ~1.5s mid-reply) avoids rebuilding a dictionary of every chat on
        // each token flush.
        if stamp { stampChanges(); snapshotConfigurations() }
        // Encode WITHOUT transcripts — they live in per-chat sidecars (written by
        // updateTranscript), so data.json stays small and cheap to re-encode. The
        // in-memory configurations keep their transcripts; only this encoded copy is slim.
        var slim = configurations
        for i in slim.indices { slim[i].transcript = [] }
        let state = PersistedState(configurations: slim, settings: settings, savedTeams: savedTeams,
                                   deletedConfigIDs: Array(deletedConfigIDs),
                                   syncBaseline: Dictionary(syncBaseline.map { ($0.key.uuidString, $0.value) },
                                                            uniquingKeysWith: { a, _ in a }))
        let url = storeURL
        writeTask?.cancel()
        // Cancellation alone can't order the writes: a detached task past its
        // cancellation check can still land AFTER a newer write. Every write goes
        // through the serializer with this save's generation, so a stale snapshot is
        // dropped instead of overwriting newer state.
        saveGeneration += 1
        let generation = saveGeneration
        // On quit (flushSaves → sync) write on THIS thread: a detached task might not
        // finish before the process exits, losing the last few seconds of metadata.
        if sync {
            do { try saveSerializer.write(JSONEncoder().encode(state), to: url, generation: generation) }
            catch { DiagnosticsLog.record("Final save failed: \(error.localizedDescription)") }
            return true
        }
        writeTask = Task.detached(priority: .utility) { [weak self, saveSerializer] in
            do {
                let data = try JSONEncoder().encode(state)
                guard !Task.isCancelled else { return }
                try saveSerializer.write(data, to: url, generation: generation)
            } catch {
                await MainActor.run { self?.show(.failure(self?.t("banner.saveFailed", error.localizedDescription) ?? "\(error)")) }
            }
        }
        return true
    }

    /// Bump `updatedAt` on configurations whose portable content changed since the
    /// last save (or which are brand new), so sync can resolve conflicts.
    private func stampChanges() {
        let now = Date()
        for i in configurations.indices {
            let c = configurations[i]
            if let prev = savedSnapshot[c.id] {
                if !c.hasSameContent(as: prev) { configurations[i].updatedAt = now }
            } else if c.updatedAt == .distantPast {
                configurations[i].updatedAt = now
            }
        }
    }

    private func snapshotConfigurations() {
        savedSnapshot = Dictionary(configurations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func load() {
        let url = storeURL
        // First launch: no store yet — start empty, saving is fine.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            // The store exists but can't be read (truncated by a force-quit, a
            // corrupt byte, a newer schema…). Starting empty is unavoidable, but
            // the next save() would overwrite the file and destroy every chat,
            // team and setting — so preserve it first and tell the user.
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("data-corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            show(.failure(t("banner.storeCorrupt", backup.lastPathComponent)))
            return
        }
        let state = decoded.migrated()
        configurations = state.configurations
        settings = state.settings
        savedTeams = state.savedTeams
        deletedConfigIDs = Set(state.deletedConfigIDs)
        syncBaseline = Dictionary(uniqueKeysWithValues: state.syncBaseline.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        // Hydrate transcripts from their sidecars — but only the ones the first frame
        // needs: an OLD data.json's inline transcript is migrated to a sidecar NOW
        // (synchronously, before any save() can strip the inline copy — a transcript
        // can never be lost), and the restored selection loads eagerly because its
        // ChatViewModel is built on the first render. Every other chat hydrates off
        // the main actor after launch (hydrateRemainingTranscripts, below) or on
        // demand, so launch cost no longer scales with the user's total chat history.
        let restoredID = settings.lastSelectedConfigID
            .flatMap { last in configurations.first { $0.id.uuidString == last }?.id }
            ?? configurations.first?.id
        for i in configurations.indices {
            let id = configurations[i].id
            if !configurations[i].transcript.isEmpty || id == restoredID {
                if let t = loadTranscript(id) {
                    configurations[i].transcript = t
                } else if !configurations[i].transcript.isEmpty {
                    writeTranscript(id, configurations[i].transcript, sync: true)   // migrate inline → sidecar
                }
            } else {
                unhydratedTranscriptIDs.insert(id)
            }
        }
        // Crash-during-undo-window sweep: deleteConfiguration defers link cleanup +
        // sidecar deletion to an in-memory timer, so a hard death inside the window
        // leaks them forever. Dangling continuedFrom links (cosmetic) are nilled here;
        // sidecars are GC'd only for TOMBSTONED ids — see sweepDeletedSidecars.
        let liveIDs = Set(configurations.map(\.id))
        for i in configurations.indices {
            if let from = configurations[i].continuedFrom, !liveIDs.contains(from) {
                configurations[i].continuedFrom = nil
            }
        }
        sweepDeletedSidecars()
        // Restore the last session's UI: selected chat + activity-panel visibility.
        selectedConfigID = restoredID   // hydrated eagerly above
        // Restore the last-open team, if it still exists.
        if let lastTeam = settings.lastSelectedTeamID,
           let team = savedTeams.first(where: { $0.id.uuidString == lastTeam }) {
            selectedTeamID = team.id
        }
        showActivity = settings.showActivity
        snapshotConfigurations()
        hydrateRemainingTranscripts()   // then retitles legacy auto-titles (needs transcripts)
    }

    /// Delete transcript/activity sidecars left behind by a delete whose undo window
    /// never finished (hard crash, kill -9, power loss): the chat is tombstoned and
    /// already gone from data.json, but the deferred finalizeDelete lived only in
    /// memory. Deliberately conservative — only files named exactly
    /// `<tombstoned-uuid>.json` are removed, so parked `.corrupt-*` backups and the
    /// sidecars of live (or merely undecodable) chats are never touched.
    private func sweepDeletedSidecars() {
        guard !deletedConfigIDs.isEmpty else { return }
        let fm = FileManager.default
        for sub in ["transcripts", "activity"] {
            let dir = storeDirectory.appendingPathComponent(sub, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "json" {
                let base = entry.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: base), deletedConfigIDs.contains(id) else { continue }
                try? fm.removeItem(at: entry)
            }
        }
    }

    /// Remember the selected chat + team so they reopen on next launch (device-local).
    func rememberSelection() {
        let id = selectedConfigID?.uuidString
        let teamID = selectedTeamID?.uuidString
        guard settings.lastSelectedConfigID != id
                || settings.lastSelectedTeamID != teamID else { return }
        settings.lastSelectedConfigID = id
        settings.lastSelectedTeamID = teamID
        save(stamp: false)
        // The selection just moved — release the now-idle chats' ViewModels.
        evictIdleChatVMs()
    }

    // MARK: - Sync merge

    /// Merge configurations pulled from the cloud into the local set using
    /// last-writer-wins by `updatedAt`, then return the merged portable set to push
    /// back. Device-local repo bindings are always preserved (never synced).
    func mergeRemote(_ remote: [PortableConfiguration]) -> [PortableConfiguration] {
        let outcome = ConfigMerger.merge(local: configurations, remote: remote,
                                         baseline: syncBaseline,
                                         conflictSuffix: " " + t("sync.conflictSuffix"))
        configurations = outcome.configurations
        // A chat deleted here must NOT come back because the remote still has it: drop
        // any tombstoned id the merge re-introduced.
        if !deletedConfigIDs.isEmpty {
            configurations.removeAll { deletedConfigIDs.contains($0.id) }
        }
        // A real divergent edit was preserved (not overwritten): tell the user so they
        // can reconcile the "(conflict)" copy instead of it vanishing silently.
        if outcome.conflictCount > 0 {
            show(.success(t("sync.conflictKept", outcome.conflictCount)))
        }
        // Record the post-merge timestamps as the new sync baseline, so the NEXT merge
        // can tell an independent local edit from a merely-stale copy.
        syncBaseline = Dictionary(configurations.map { ($0.id, $0.updatedAt) },
                                  uniquingKeysWith: { a, _ in a })
        if selectedConfigID == nil { selectedConfigID = configurations.first?.id }
        // Don't re-stamp: timestamps are already authoritative after the merge.
        save(stamp: false)
        return configurations.map(\.portable)
    }
}

/// Orders the data.json writes issued by `AppModel.save()`. The detached write tasks
/// are otherwise unordered (cancellation is only checked before the write starts), so
/// a stale snapshot that already passed its check could atomically replace a NEWER
/// write — including the final synchronous one on quit. The lock is held across the
/// write so check-then-write is atomic; a write whose generation isn't newer than the
/// last one written is silently dropped.
final class SaveSerializer: @unchecked Sendable {
    private let lock = NSLock()
    private var lastWrittenGeneration: UInt64 = 0

    /// Write `data` to `url` atomically, unless a newer generation already wrote.
    func write(_ data: Data, to url: URL, generation: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        guard generation > lastWrittenGeneration else { return }
        try data.write(to: url, options: .atomic)
        lastWrittenGeneration = generation
    }

    /// Mark every generation up to `generation` as already written WITHOUT writing,
    /// so an in-flight write at or below it is dropped. Used just before deleting the
    /// file — a straggling detached write must not re-create it.
    func barrier(upTo generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        lastWrittenGeneration = max(lastWrittenGeneration, generation)
    }
}
