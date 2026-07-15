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

@Observable
@MainActor
final class AppModel {

    // MARK: - State

    var configurations: [Configuration] = []
    var selectedConfigID: Configuration.ID?
    var settings = AppSettings()

    /// Global library of named team presets, reusable across chats.
    var savedTeams: [SavedTeam] = []
    /// The team currently open in the Team section (independent of the selected chat).
    var selectedTeamID: SavedTeam.ID?

    /// A team being configured but NOT yet saved: picking a strategy opens this
    /// draft in the editor; it only joins `savedTeams` when the user hits "Create".
    /// Navigating away with a draft prompts a discard confirmation.
    var draftTeam: SavedTeam?
    /// A pending navigation deferred while the discard-draft confirmation is shown.
    @ObservationIgnored private var pendingLeave: (() -> Void)?
    /// Drives the "discard this draft team?" confirmation.
    var showDiscardDraftConfirm = false

    // MARK: - Providers
    /// Providers whose CLI is currently installed/detected. Drives locked vs
    /// selectable state in the model/provider pickers.
    var connectedProviders: Set<AIProvider> = [.claude]

    /// Re-show the first-run onboarding on demand (from the Lab), so it can be
    /// reviewed without wiping the `didOnboard` flag / reinstalling.
    var showOnboardingPreview = false

    /// Re-detect which provider CLIs are installed (off the main thread).
    func refreshConnectedProviders() async {
        var found: Set<AIProvider> = []
        for p in AIProvider.allCases {
            let name = settings.binary(for: p)
            if await Task.detached(operation: { ClaudeRunner.resolveBinary(name) }).value != nil {
                found.insert(p)
            }
        }
        connectedProviders = found
    }

    /// Whether a provider can be selected right now (its CLI is installed).
    func isConnected(_ provider: AIProvider) -> Bool { connectedProviders.contains(provider) }

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

    /// API keys to hand the provider runner — only OpenAI's, and only when the user
    /// opted into API-key mode (which re-enables explicit model selection for Codex).
    func providerAPIKeys() -> [AIProvider: String] {
        guard settings.openaiUseAPIKey, let key = openAIAPIKey else { return [:] }
        return [.openai: key]
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
    enum NavSection { case chats, services, team, usage, loops, advisor, particleLab, code, skills, settings }
    var navSection: NavSection = .chats

    /// The chat that should open directly in Code Mode (set by the Code launcher;
    /// ChatView consumes it once on appear).
    var openInCodeMode: Configuration.ID?

    // MARK: - Usage (real Claude token usage from local logs)
    /// Aggregated Claude usage read from ~/.claude logs (nil until first refresh).
    var claudeUsage: UsageSummary?
    /// Real Codex usage (authoritative % + reset) read from ~/.codex logs.
    var codexUsage: CodexUsage?
    /// Real Claude rate-limit percentages from Claude's own usage endpoint (needs a
    /// valid login). nil when signed out or the request fails.
    var claudeExact: ClaudeUsageAPI.Exact?
    /// True while a usage refresh is in flight.
    var isRefreshingUsage = false

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
    func refreshUsage(includeExact: Bool = false) async {
        isRefreshingUsage = true
        async let claude = Task.detached(priority: .utility) { ClaudeUsageStore.load() }.value
        async let codex = Task.detached(priority: .utility) { CodexUsageStore.load() }.value
        claudeUsage = await claude
        codexUsage = await codex
        isRefreshingUsage = false
        if includeExact { await refreshExactUsage() }
    }

    /// Whether we've already attempted the Keychain-backed exact-usage fetch this session
    /// — so a missing/expired token prompts (or no-ops) at most ONCE, never repeatedly.
    @ObservationIgnored private var didAttemptExactUsage = false

    /// Fetch Claude's authoritative rate-limit % from its usage endpoint. This reads the
    /// Claude Code login token from the Keychain (which can prompt for the password), so
    /// it runs ONLY on deliberate intent — opening the Usage section or an explicit
    /// refresh — never at launch. Attempted once per session unless `force` is set (the
    /// manual "refresh" / just-signed-in cases). Cached in `claudeExact` once it lands.
    func refreshExactUsage(force: Bool = false) async {
        guard force || !didAttemptExactUsage else { return }
        didAttemptExactUsage = true
        if let exact = await Task.detached(priority: .utility, operation: { await ClaudeUsageAPI.fetch() }).value {
            claudeExact = exact
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
    var showSidebar = true
    var showInspector = false
    /// Right-side agent-activity panel visibility (persisted so it's restored).
    var showActivity = false {
        didSet { if showActivity != oldValue { settings.showActivity = showActivity; save(stamp: false) } }
    }

    /// Transient banner shown after actions.
    enum Banner: Equatable {
        case success(String)
        case failure(String)
    }
    var banner: Banner?

    /// Live security-scoped URLs from this session's folder pickers, keyed by the
    /// owning configuration id. Avoids re-resolving bookmarks mid-session. This is
    /// a transient cache, not UI state — kept out of observation so resolving a
    /// bookmark during a view's body (in `repoURL(for:)`) does not mutate observed
    /// state mid-render.
    @ObservationIgnored
    private var liveRepoURLs: [Configuration.ID: URL] = [:]

    /// Token used to cancel a pending auto-dismiss when a new banner appears.
    @ObservationIgnored private var bannerDismissTask: Task<Void, Never>?

    // MARK: - Chat run lifetime (AppModel-owned VM cache)

    /// One ChatViewModel per chat, owned here (not by the view) so a running turn
    /// survives navigation away from the chat. Not observed: views get their VM
    /// through `chatViewModel(for:)`, and lazily filling this cache from a view
    /// body must not mutate observed state mid-render.
    @ObservationIgnored private var chatVMs: [Configuration.ID: ChatViewModel] = [:]
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

    init() {
        load()
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
    private static let beginnerKeys: Set<String> = ["strat.solo", "strat.execadv", "strat.planner"]

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
    func flashSuccess(_ message: String) { show(.success(message)) }

    /// Public helper for views/services to show a sticky failure banner. Every
    /// failure is also written to the diagnostics log so it can be exported later.
    func flashFailure(_ message: String) {
        DiagnosticsLog.record(message)
        show(.failure(message))
    }

    /// True while the current banner is a failure — the capsule then offers the
    /// "Export log" / "Fix" actions.
    var bannerIsFailure: Bool { if case .failure = banner { return true } else { return false } }

    /// Save the diagnostics log to a user-chosen file (for sharing when something
    /// went wrong). Shared by Settings and the failure banner.
    func exportDiagnostics() {
        let contents = DiagnosticsLog.contents()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "coral-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
    func dismissBanner() {
        withAnimation {
            banner = nil
            bannerDismissTask?.cancel()
        }
    }

    /// Show a banner; success banners auto-dismiss after a few seconds, errors stay.
    private func show(_ banner: Banner) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.banner = banner
        }
        bannerDismissTask?.cancel()
        if case .success = banner {
            bannerDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if self.banner == banner {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.banner = nil
                    }
                }
            }
        }
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
        configurations[i].name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        configurations[i].titleWasManuallySet = true
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

    func deleteConfiguration(_ id: Configuration.ID) {
        invalidateChatVM(id)
        configurations.removeAll { $0.id == id }
        liveRepoURLs[id] = nil
        try? FileManager.default.removeItem(at: activityURL(id))     // drop the history sidecar
        try? FileManager.default.removeItem(at: transcriptURL(id))   // and the transcript sidecar
        if selectedConfigID == id { selectedConfigID = configurations.first?.id }
        save()
    }

    /// Duplicate a configuration (fresh id + name suffix). The copy keeps the same
    /// repo binding so re-generating into the same repo is one click away.
    func duplicateConfiguration(_ id: Configuration.ID) {
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
        // The copy carries the source's transcript in memory — write its sidecar so it
        // survives the transcript-stripped data.json save (else it'd be lost on reload).
        if !copy.transcript.isEmpty { writeTranscript(copy.id, copy.transcript) }
        save()
    }

    /// Import an existing repo's `.claude/` config back into an editable Strategy,
    /// binding the new configuration to that repo (so it round-trips / re-exports).
    func importFromRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("common.choose")
        panel.message = t("import.pickMessage")
        if let base = resolvedDefaultReposURL() { panel.directoryURL = base }
        guard panel.runModal() == .OK, let url = panel.url else { return }

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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("common.choose")
        panel.message = t("import.pickMessage")
        if let base = resolvedDefaultReposURL() { panel.directoryURL = base }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTeamFromRepo(at: url)
    }

    // MARK: - Strategy document (.sfstrategy) export / import

    /// Export a configuration's strategy as a shareable `.sfstrategy` document
    /// (topology only — never repo paths/bookmarks).
    func exportStrategyDocument(_ config: Configuration) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = StrategyPackage.fileName(for: config.strategy)
        panel.allowedContentTypes = [.sfStrategy]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StrategyPackage.export(config.strategy).write(to: url, options: .atomic)
            flashSuccess(t("doc.exported"))
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
        }
    }

    /// Import a `.sfstrategy` document as a new (repo-less) configuration.
    func importStrategyDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.sfStrategy]
        panel.prompt = t("common.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        configurations[i].strategy = template
        configurations[i].strategyIsAuto = false   // user/AI chose a team explicitly
        save()   // persist the strategy change so it survives relaunch
        flashSuccess(t("team.applied", strategyDisplayName(template)))
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
        configurations[i].strategy = team.strategyCopy()
        configurations[i].strategyIsAuto = false   // user chose a team explicitly
        save()
        flashSuccess(t("team.applied", team.name))
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
                                                             deprioritize: deprioritizedProviders)
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
        flashSuccess(t("team.share.copied"))
    }

    /// Export a team to a shareable `.sfstrategy` file.
    func exportTeamDocument(_ team: SavedTeam) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = StrategyPackage.fileName(for: team.strategy)
        panel.allowedContentTypes = [.sfStrategy]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StrategyPackage.export(team.strategy).write(to: url, options: .atomic)
            Analytics.log(.strategyShared(kind: "file"))
            flashSuccess(t("doc.exported"))
        } catch {
            show(.failure(t("banner.writeFailed", error.localizedDescription)))
        }
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.sfStrategy]
        panel.prompt = t("common.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
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

    /// Force any pending coalesced write to disk immediately (call on background/quit).
    func flushSaves() {
        guard let work = pendingSave else { return }
        work.cancel(); pendingSave = nil; pendingSaveSince = nil
        _ = save(stamp: false)
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
            _ = try StrategyWriter(repoURL: url, binary: settings.claudeBinary).write(strategy: config.strategy)
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
        let dir = AppPaths.supportDirectory().appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Write one chat's transcript to its sidecar, atomically. Synchronous and cheap
    /// (one chat, not all) — and crash-safe: the sidecar exists before save() strips the
    /// inline copy from data.json.
    private func writeTranscript(_ id: Configuration.ID, _ messages: [ChatMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: transcriptURL(id), options: .atomic)
    }

    private func loadTranscript(_ id: Configuration.ID) -> [ChatMessage]? {
        guard let data = try? Data(contentsOf: transcriptURL(id)) else { return nil }
        return try? JSONDecoder().decode([ChatMessage].self, from: data)
    }

    // MARK: - Agent activity history (device-local, per-chat sidecar — never synced)

    private func activityURL(_ id: Configuration.ID) -> URL {
        let dir = AppPaths.supportDirectory().appendingPathComponent("activity", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    /// The persisted turn-by-turn agent history for a chat (empty if none).
    func loadActivity(_ id: Configuration.ID) -> [TurnActivity] {
        guard let data = try? Data(contentsOf: activityURL(id)) else { return [] }
        return (try? JSONDecoder().decode([TurnActivity].self, from: data)) ?? []
    }

    /// Append one finished turn, capped to the last 50, written atomically. Does NOT
    /// touch data.json / save() — no sync, no mid-stream store rewrites.
    func appendActivity(_ id: Configuration.ID, _ turn: TurnActivity) {
        var all = loadActivity(id)
        all.append(turn)
        if all.count > 50 { all = Array(all.suffix(50)) }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: activityURL(id), options: .atomic)
        }
    }

    // MARK: - Chat view-model lookup

    /// The (cached) view model for a chat. Creates it on first use and keeps it
    /// alive across navigation, so a running turn keeps streaming off-screen.
    /// Safe to call from a view body: it only touches @ObservationIgnored storage
    /// and refreshes the VM's (unobserved-by-callers) config snapshot.
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
            providerBinaries: Dictionary(uniqueKeysWithValues:
                AIProvider.allCases.map { ($0, settings.binary(for: $0)) }),
            providerAPIKeys: providerAPIKeys(),
            codexReasoningEffort: settings.codexReasoningEffort,
            permissionMode: settings.chatAutonomy.permissionMode,
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("repo.picker.prompt")
        if let base = resolvedDefaultReposURL() { panel.directoryURL = base }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openCodeChat(repoURL: url)
    }

    // MARK: - Repo selection

    /// Present an open panel to choose the target repo folder for a configuration.
    /// Returns true iff the user actually picked a folder.
    @discardableResult
    func pickRepo(for id: Configuration.ID) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("repo.picker.prompt")
        panel.message = t("repo.picker.message")
        if let base = resolvedDefaultReposURL() { panel.directoryURL = base }

        guard panel.runModal() == .OK, let url = panel.url,
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("repo.picker.prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        if let data = config.repoBookmark, let url = resolveBookmark(data) {
            liveRepoURLs[config.id] = url
            return url
        }
        if let path = config.repoPath { return URL(fileURLWithPath: path) }
        return nil
    }

    private func resolvedDefaultReposURL() -> URL? {
        if let data = settings.defaultReposBookmark, let url = resolveBookmark(data) { return url }
        if let path = settings.defaultReposPath { return URL(fileURLWithPath: path) }
        return nil
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    // MARK: - Preview

    /// Files that would be written for a configuration, merged against disk.
    func previewFiles(for config: Configuration) -> [GeneratedFile] {
        if let url = repoURL(for: config) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return StrategyWriter(repoURL: url, binary: settings.claudeBinary)
                .previewFiles(for: config.strategy)
        }
        // No repo yet: still preview agent files + a from-scratch CLAUDE.md.
        var files = AgentFileGenerator.generate(for: config.strategy)
        let claude = ClaudeMdGenerator.merged(existing: nil, strategy: config.strategy, binary: settings.claudeBinary)
        files.append(GeneratedFile(relativePath: ClaudeMdGenerator.fileName, contents: claude))
        return files
    }

    /// A pre-write diff of every file that would be written — what changes on disk
    /// before anything is written. When no repo is chosen yet, everything is "created".
    func previewDiffs(for config: Configuration) -> [FileDiff] {
        if let url = repoURL(for: config) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return StrategyWriter(repoURL: url, binary: settings.claudeBinary)
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
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let writer = StrategyWriter(repoURL: url, binary: settings.claudeBinary)
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
            show(.success(t("banner.wrote", written.count, url.lastPathComponent)))
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = StandaloneBriefGenerator.fileName(for: config.strategy)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = t("common.choose")
        panel.message = t("setup.sample.sub")
        guard panel.runModal() == .OK, let parent = panel.url else { return }

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

        init(configurations: [Configuration],
             settings: AppSettings,
             savedTeams: [SavedTeam] = [],
             schemaVersion: Int = currentVersion) {
            self.schemaVersion = schemaVersion
            self.configurations = configurations
            self.settings = settings
            self.savedTeams = savedTeams
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, configurations, settings, savedTeams }

        // Tolerant decode: older files have no schemaVersion (→ 0). Missing
        // settings/savedTeams default rather than failing the whole load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            configurations = try c.decodeIfPresent([Configuration].self, forKey: .configurations) ?? []
            settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
            savedTeams = try c.decodeIfPresent([SavedTeam].self, forKey: .savedTeams) ?? []
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
        AppPaths.supportDirectory().appendingPathComponent("data.json")
    }

    /// Coalesces rapid saves; a new save supersedes an in-flight write.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// Persist the store. Encoding + disk I/O run OFF the main actor and are
    /// coalesced, so streaming a reply (which saves on every chunk) never blocks the
    /// UI re-writing the whole store synchronously. Returns optimistically; a write
    /// failure surfaces as a banner.
    @discardableResult
    func save(stamp: Bool = true) -> Bool {
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
        let state = PersistedState(configurations: slim, settings: settings, savedTeams: savedTeams)
        let url = storeURL
        writeTask?.cancel()
        writeTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try JSONEncoder().encode(state)
                guard !Task.isCancelled else { return }
                try data.write(to: url, options: .atomic)
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
        // Hydrate transcripts from their sidecars. For an OLD data.json that still carried
        // transcripts inline, migrate each to a sidecar NOW (synchronously, before any
        // save() can strip the inline copy) so a transcript can never be lost.
        for i in configurations.indices {
            let id = configurations[i].id
            if let t = loadTranscript(id) {
                configurations[i].transcript = t
            } else if !configurations[i].transcript.isEmpty {
                writeTranscript(id, configurations[i].transcript)   // migrate inline → sidecar
            }
        }
        // Restore the last session's UI: selected chat + activity-panel visibility.
        if let last = settings.lastSelectedConfigID,
           let restored = configurations.first(where: { $0.id.uuidString == last }) {
            selectedConfigID = restored.id
        } else {
            selectedConfigID = configurations.first?.id
        }
        // Restore the last-open team, if it still exists.
        if let lastTeam = settings.lastSelectedTeamID,
           let team = savedTeams.first(where: { $0.id.uuidString == lastTeam }) {
            selectedTeamID = team.id
        }
        showActivity = settings.showActivity
        snapshotConfigurations()
        retitleAutoNamedChats()   // upgrade legacy auto-titles in place (idempotent)
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
    }

    // MARK: - Sync merge

    /// Merge configurations pulled from the cloud into the local set using
    /// last-writer-wins by `updatedAt`, then return the merged portable set to push
    /// back. Device-local repo bindings are always preserved (never synced).
    func mergeRemote(_ remote: [PortableConfiguration]) -> [PortableConfiguration] {
        configurations = ConfigMerger.merge(local: configurations, remote: remote)
        if selectedConfigID == nil { selectedConfigID = configurations.first?.id }
        // Don't re-stamp: timestamps are already authoritative after the merge.
        save(stamp: false)
        return configurations.map(\.portable)
    }
}
