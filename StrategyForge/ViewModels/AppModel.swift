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

    // MARK: - Providers
    /// Providers whose CLI is currently installed/detected. Drives locked vs
    /// selectable state in the model/provider pickers.
    var connectedProviders: Set<AIProvider> = [.claude]

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

    /// Which top-level section the nav rail shows: the chats, or connected services.
    enum NavSection { case chats, services, team }
    var navSection: NavSection = .chats
    /// The service shown in the main area while in the Services section.
    var selectedService: AIProvider = .claude

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

    /// Show a banner; success banners auto-dismiss after a few seconds, errors stay.
    private func show(_ banner: Banner) {
        self.banner = banner
        bannerDismissTask?.cancel()
        if case .success = banner {
            bannerDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if self.banner == banner { self.banner = nil }
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
        // auto-titling from the first message). Executor+Advisor is the gentlest
        // default strategy.
        let config = Configuration(
            name: "",
            strategy: StrategyLibrary.executorAdvisor(),
            lastActiveAt: Date()   // newest chat sorts to the top
        )
        configurations.append(config)
        selectedConfigID = config.id
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

    /// Name an untitled chat from its first user message (first line, ≤40 chars).
    /// No-op if the user already named it or a name exists.
    func autoTitleIfNeeded(_ id: Configuration.ID, fromFirstMessage text: String) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        guard !configurations[i].titleWasManuallySet, configurations[i].name.isEmpty else { return }
        let firstLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstLine.isEmpty else { return }
        let capped = firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
        configurations[i].name = capped   // leave titleWasManuallySet false (still auto)
        save()
    }

    func deleteConfiguration(_ id: Configuration.ID) {
        configurations.removeAll { $0.id == id }
        liveRepoURLs[id] = nil
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

        guard !agentFiles.isEmpty || claudeMd != nil else {
            show(.failure(t("import.notFound")))
            return
        }

        let strategy = ClaudeConfigParser.parse(
            agentFiles: agentFiles.sorted { $0.fileName < $1.fileName },
            claudeMd: claudeMd,
            fallbackName: url.lastPathComponent
        )
        var config = Configuration(name: strategy.name, strategy: strategy, repoPath: url.path)
        config.repoBookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
        configurations.append(config)
        selectedConfigID = config.id
        liveRepoURLs[config.id] = url
        save()
        flashSuccess(t("import.done", strategy.subagentRoles.count))
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
            let strategy = try StrategyPackage.import(data)
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
        save()   // persist the strategy change so it survives relaunch
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
        save()
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
        save(stamp: false)
    }

    /// Write the strategy's `.claude` files into the chat's repo without any UI
    /// banner — so a chat run actually uses the configured team. Idempotent.
    func writeStrategyFilesQuietly(_ id: Configuration.ID) {
        guard let config = configurations.first(where: { $0.id == id }),
              config.strategy.isValid,
              let url = repoURL(for: config) else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        _ = try? StrategyWriter(repoURL: url, binary: settings.claudeBinary).write(strategy: config.strategy)
        if let i = configurations.firstIndex(where: { $0.id == id }) {
            configurations[i].lastGeneratedAt = Date()
            save(stamp: false)
        }
    }

    /// Persist a chat's unsent draft. Device-local (stamp: false); no-op if unchanged.
    func updateDraft(_ id: Configuration.ID, _ text: String) {
        guard let i = configurations.firstIndex(where: { $0.id == id }),
              configurations[i].draft != text else { return }
        configurations[i].draft = text
        save(stamp: false)
    }

    /// Persist a chat's cumulative token/cost usage. Device-local (stamp: false).
    func updateUsage(_ id: Configuration.ID, tokens: Int, costUSD: Double) {
        guard let i = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[i].totalTokens = tokens
        configurations[i].totalCostUSD = costUSD
        save(stamp: false)
    }

    // MARK: - Repo selection

    /// Present an open panel to choose the target repo folder for a configuration.
    func pickRepo(for id: Configuration.ID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose repository"
        panel.message = "Select the local repository where StrategyForge will write the Claude Code config."
        if let base = resolvedDefaultReposURL() { panel.directoryURL = base }

        guard panel.runModal() == .OK, let url = panel.url,
              let i = configurations.firstIndex(where: { $0.id == id }) else { return }

        configurations[i].repoPath = url.path
        configurations[i].repoBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        liveRepoURLs[id] = url
        save()
    }

    /// Present an open panel to choose the default repos folder (Settings).
    func pickDefaultReposFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
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
            let written = try StrategyWriter(repoURL: url, binary: settings.claudeBinary)
                .write(strategy: config.strategy)
            if let i = configurations.firstIndex(where: { $0.id == config.id }) {
                configurations[i].lastGeneratedAt = Date()
                save()
            }
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
            .appendingPathComponent("StrategyForge-\(UUID().uuidString).command")
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
        pickRepo(for: config.id)
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
        let sample = parent.appendingPathComponent("StrategyForge Sandbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
            try "# Practice project\n\nMade by StrategyForge. Ask Claude to add a file here — you can delete this whole folder anytime.\n"
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("StrategyForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    @discardableResult
    func save(stamp: Bool = true) -> Bool {
        if stamp { stampChanges() }
        let state = PersistedState(configurations: configurations, settings: settings, savedTeams: savedTeams)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: storeURL, options: .atomic)
            snapshotConfigurations()
            return true
        } catch {
            show(.failure(t("banner.saveFailed", error.localizedDescription)))
            return false
        }
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
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        let state = decoded.migrated()
        configurations = state.configurations
        settings = state.settings
        // Restore the last session's UI: selected chat + activity-panel visibility.
        if let last = settings.lastSelectedConfigID,
           let restored = configurations.first(where: { $0.id.uuidString == last }) {
            selectedConfigID = restored.id
        } else {
            selectedConfigID = configurations.first?.id
        }
        showActivity = settings.showActivity
        snapshotConfigurations()
    }

    /// Remember the selected chat so it reopens on next launch (device-local).
    func rememberSelection() {
        let id = selectedConfigID?.uuidString
        guard settings.lastSelectedConfigID != id else { return }
        settings.lastSelectedConfigID = id
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
