//
//  ChatViewModel.swift
//  StrategyForge
//
//  Drives the headless-Claude chat: sends a turn, streams the reply, and keeps a
//  simple message list. It runs Claude Code in the configuration's repo, so the
//  generated strategy (.claude/agents + CLAUDE.md) is honored automatically and it
//  uses the user's own plan.
//

import Foundation
import Observation

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
}

/// Reasoning effort for a turn — from fastest to most thorough. Steers how hard the
/// model thinks by appending the corresponding "think"/"ultrathink" keyword (which
/// Claude Code recognizes) to the real prompt.
enum Effort: String, CaseIterable, Identifiable, Codable {
    case fast, medium, high, ultra
    var id: String { rawValue }
    var labelKey: String { "effort.level.\(rawValue)" }
    var blurbKey: String { "effort.level.\(rawValue).blurb" }
    /// Position on the Faster ↔ Smarter slider (0…3).
    var sliderValue: Double { Double(Self.allCases.firstIndex(of: self) ?? 2) }
    static func at(_ v: Double) -> Effort {
        let i = min(max(Int(v.rounded()), 0), allCases.count - 1)
        return allCases[i]
    }
    /// Appended to the real prompt (never the transcript display text).
    var promptDirective: String {
        switch self {
        case .fast:   return ""
        case .medium: return "\n\nThink about this before answering."
        case .high:   return "\n\nThink hard about this before you answer."
        case .ultra:  return "\n\nUltrathink: reason very carefully and thoroughly before answering."
        }
    }
}

/// One entry in the live agent-activity timeline. Codable so it can be persisted
/// into the per-chat activity history (device-local).
struct ActivityStep: Identifiable, Hashable, Codable {
    var id = UUID()
    let title: String
    let detail: String?
    let at: Date
    let isDelegation: Bool
    /// Which agent performed this step — nil means the orchestrator. Used to
    /// attribute steps to a subagent for the per-agent drill-down.
    var agent: String? = nil

    init(title: String, detail: String?, at: Date, isDelegation: Bool, agent: String? = nil) {
        self.title = title; self.detail = detail; self.at = at
        self.isDelegation = isDelegation; self.agent = agent
    }
    enum CodingKeys: String, CodingKey { case id, title, detail, at, isDelegation, agent }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
        isDelegation = try c.decodeIfPresent(Bool.self, forKey: .isDelegation) ?? false
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
    }
}

/// One shell command the agent ran, with its output (for the code-mode terminal).
struct CommandRun: Identifiable, Hashable, Codable {
    var id = UUID()
    let command: String
    let output: String
    let at: Date

    init(command: String, output: String, at: Date) {
        self.command = command; self.output = output; self.at = at
    }
    enum CodingKeys: String, CodingKey { case id, command, output, at }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        output = try c.decodeIfPresent(String.self, forKey: .output) ?? ""
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
    }
}

/// A live tool-permission request from the CLI ("Ask" mode), awaiting a decision.
struct PendingPermission: Identifiable, Equatable {
    let id: String
    let toolName: String
    let detail: String
}

/// Tokens (and prorated cost) spent by one model during a run — the #8 breakdown.
struct ModelSpend: Codable, Hashable, Identifiable {
    var id: String { model }
    let model: String
    var tokens: Int
    var costUSD: Double
}

/// A persisted record of one finished turn's agent activity (device-local, per chat)
/// — the #7 reviewable history. Tolerant decode so older/newer files never fail.
struct TurnActivity: Identifiable, Codable, Hashable {
    var id = UUID()
    var turnIndex: Int
    var prompt: String
    var startedAt: Date
    var endedAt: Date
    var steps: [ActivityStep]
    var agentsInvolved: [String]
    var commandLog: [CommandRun]
    var tokensUsed: Int
    var costUSD: Double
    var byModel: [ModelSpend]
    var byAgent: [String: Int]
    /// Agent Skills the model pulled in during this turn (slugs, de-duplicated).
    var skillsUsed: [String]
    /// Absolute paths of files the agents wrote/edited during this turn — persisted so
    /// the produced files survive relaunch and stay recoverable from the activity panel.
    var files: [String]

    init(turnIndex: Int, prompt: String, startedAt: Date, endedAt: Date,
         steps: [ActivityStep], agentsInvolved: [String], commandLog: [CommandRun],
         tokensUsed: Int, costUSD: Double, byModel: [ModelSpend], byAgent: [String: Int],
         skillsUsed: [String] = [], files: [String] = []) {
        self.turnIndex = turnIndex; self.prompt = prompt
        self.startedAt = startedAt; self.endedAt = endedAt
        self.steps = steps; self.agentsInvolved = agentsInvolved; self.commandLog = commandLog
        self.tokensUsed = tokensUsed; self.costUSD = costUSD
        self.byModel = byModel; self.byAgent = byAgent
        self.skillsUsed = skillsUsed
        self.files = files
    }
    enum CodingKeys: String, CodingKey {
        case id, turnIndex, prompt, startedAt, endedAt, steps, agentsInvolved
        case commandLog, tokensUsed, costUSD, byModel, byAgent, skillsUsed, files
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        turnIndex = try c.decodeIfPresent(Int.self, forKey: .turnIndex) ?? 0
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? .distantPast
        steps = try c.decodeIfPresent([ActivityStep].self, forKey: .steps) ?? []
        agentsInvolved = try c.decodeIfPresent([String].self, forKey: .agentsInvolved) ?? []
        commandLog = try c.decodeIfPresent([CommandRun].self, forKey: .commandLog) ?? []
        tokensUsed = try c.decodeIfPresent(Int.self, forKey: .tokensUsed) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        byModel = try c.decodeIfPresent([ModelSpend].self, forKey: .byModel) ?? []
        byAgent = try c.decodeIfPresent([String: Int].self, forKey: .byAgent) ?? [:]
        skillsUsed = try c.decodeIfPresent([String].self, forKey: .skillsUsed) ?? []
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
    }
}

/// A staged attachment: the name shown to the user and the (possibly converted)
/// file Claude actually reads.
struct Attachment: Identifiable, Hashable {
    let id = UUID()
    let name: String   // original file name (for display)
    let url: URL       // file to hand to Claude (original or converted .txt)
}

/// A message the user submitted while a turn was still running — held in a queue and
/// sent automatically as soon as the run frees up (like Claude Code's queued input).
struct QueuedMessage: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var attachments: [Attachment]
}

@Observable
@MainActor
final class ChatViewModel {
    /// AppModel refreshes it on lookup; views must not write.
    var config: Configuration
    private let binary: String
    /// Configured CLI binaries per provider (from AppSettings), so a cross-provider
    /// meta run can resolve Codex/Gemini via the same paths that marked them
    /// connected. Empty in previews → the meta run uses just the Claude binary.
    private let providerBinaries: [AIProvider: String]
    /// Optional per-provider API keys (OpenAI) so a cross-provider meta run can use
    /// the API (which re-enables model selection) instead of the subscription default.
    private let providerAPIKeys: [AIProvider: String]
    /// Codex reasoning effort ("" = account default), passed to the meta runner.
    private let codexReasoningEffort: String

    var messages: [ChatMessage] = []
    /// Tools the agent used during the current turn (shown as a status line).
    var activity: [String] = []
    /// Absolute paths of files the agent has written/edited in this chat.
    var editedFiles: [String] = []
    /// Agent Skills the model has pulled in across this chat (slugs, unique).
    var skillsUsed: [String] = []
    /// Skills used within the current turn only — snapshotted into TurnActivity.
    @ObservationIgnored private var turnSkillsUsed: [String] = []
    /// Files written within the current turn only — snapshotted into TurnActivity so
    /// produced files persist per turn and are recoverable after relaunch.
    @ObservationIgnored private var turnEditedFiles: [String] = []
    /// The subagent the orchestrator is currently delegating to (if any).
    var activeSubagent: String?
    /// Roles executing RIGHT NOW. The meta path runs several workers concurrently, so a
    /// single `activeSubagent` can't represent them and goes stale (a finished worker
    /// looked "working" in the panel while the chat showed it done). This per-role set
    /// keeps the panel/diagram status in lockstep with the chat — no discrepancies.
    var rolesInProgress: Set<String> = []
    /// Every subagent the orchestrator has delegated to this turn, in order (unique).
    var agentsInvolved: [String] = []
    /// Tool uses the last run wasn't permitted to perform (→ offer allow & retry).
    var deniedTools: [String] = []
    /// Once the user chooses "always allow", elevate every subsequent turn in this
    /// chat to full permissions (headless has no per-prompt approval).
    var elevatedPermissions = false
    /// True when the team mixes non-Claude providers that fall back to Claude for now.
    var mixedProvidersNote = false
    /// Live timeline of what the agents did this turn (for the activity panel).
    var timeline: [ActivityStep] = []
    /// The agent's task list (from TodoWrite).
    var todos: [AgentTodo] = []
    /// Shell commands the agent ran this turn, with output (code-mode terminal).
    var commandLog: [CommandRun] = []
    /// Per-model token spend for the current turn (exact, from each message's model).
    var tokensByModel: [String: Int] = [:]
    /// Per-agent (role) token spend for the current turn — exact on the Meta path,
    /// best-effort on the native path (usage while a subagent is active).
    var tokensByAgent: [String: Int] = [:]
    /// The chat's persisted turn-by-turn agent history (device-local), for review.
    var history: [TurnActivity] = []
    /// A live tool-permission request awaiting the user's decision ("Ask" mode).
    var pendingPermission: PendingPermission?
    /// Writes the allow/deny back to the running process (set per interactive turn).
    @ObservationIgnored private var permissionResponder: PermissionResponder?
    /// Bash tool_use id → command, to pair output (tool_result) back to its command.
    @ObservationIgnored private var pendingCommands: [String: String] = [:]
    /// Meta path: remember each role's model within a turn, to attribute its tokens.
    @ObservationIgnored private var roleModels: [String: String] = [:]
    /// Meta path: the concrete task the orchestrator assigned each role this turn, so the
    /// panel/diagram can show what an agent is ACTUALLY doing (not just its generic role).
    var roleTasks: [String: String] = [:]
    /// Meta path: when each in-progress role started, so the panel can tick a live "working
    /// 2m 14s" — the one-shot CLIs don't stream, so this is the liveness signal that the
    /// team is alive (not hung) during the long, silent worker calls.
    var roleStartedAt: [String: Date] = [:]
    /// Meta path: a live, human-readable narration of what the team is doing, written
    /// into the assistant bubble as it happens (the one-shot legs don't token-stream,
    /// so without this the chat looks frozen until the final synthesis lands).
    @ObservationIgnored private var metaNarration: [String] = []
    /// When the current (in-progress) narration step began — used to tick a live
    /// elapsed timer onto it, so the bubble keeps visibly moving during the long
    /// one-shot worker/synthesis calls (which can't stream token-by-token).
    @ObservationIgnored private var narrationStepSince: Date?
    /// A 1s heartbeat that re-renders the narration while a meta turn runs.
    @ObservationIgnored private var narrationTicker: Task<Void, Never>?
    /// When the current turn started (for the elapsed timer).
    var turnStartedAt: Date?
    /// Files staged to attach to the next message for Claude to review.
    var attachments: [Attachment] = []
    /// Dirs granted for the last run (reused on allow-and-retry).
    @ObservationIgnored private var lastExtraDirs: [String] = []
    /// The real prompt of the last turn (with file paths), reused on allow-and-retry
    /// — NOT the display text, which only carries 📎 file names.
    @ObservationIgnored private var lastPromptText = ""
    var input = ""
    /// Messages the user submitted while a turn was running — sent automatically, in
    /// order, as each run finishes (Claude Code-style queued input). Empty when idle.
    var queued: [QueuedMessage] = []
    var isRunning = false {
        didSet { if isRunning != oldValue { onRunningChanged?(isRunning) } }
    }
    /// Notifies the owner (AppModel) when a turn starts/ends, so global running
    /// indicators and finish banners work even when this chat isn't on screen.
    @ObservationIgnored var onRunningChanged: ((Bool) -> Void)?
    var errorText: String?
    /// Running token total + cost for this chat, grows per turn.
    var totalTokens = 0
    var totalCostUSD = 0.0

    /// Whether a Claude Code session already exists in the repo (→ use `--continue`).
    private var hasSession = false
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// Called to persist the transcript after it changes (device-local).
    @ObservationIgnored private let persist: ([ChatMessage]) -> Void
    /// Called with the text of the very first user message (for auto-titling).
    @ObservationIgnored private let onFirstUserMessage: (String) -> Void
    /// First-message hook: may return a strategy recommended from the prompt (when
    /// the chat's team is still "auto"), which is adopted before this turn runs.
    /// Async so it can use the on-device model; returns nil instantly for chats whose
    /// team the user already chose.
    @ObservationIgnored private let autoRecommendStrategy: (String) async -> Strategy?
    /// Writes the strategy's .claude files into the repo so the run actually uses
    /// the configured team. Called right before each run (idempotent).
    @ObservationIgnored private let ensureStrategyFiles: () -> Void
    /// The permission mode for runs — now user-switchable per chat (Accept edits /
    /// Plan / Automatic), so the composer's Mode menu can change it live.
    var permissionMode: String
    /// Reasoning effort for the next turn — steers how hard the model thinks by
    /// appending a "think"/"ultrathink" directive to the real prompt (Claude Code
    /// honors these keywords). User-picked in the composer's effort control.
    var effort: Effort = .high
    /// Persists cumulative usage (tokens, cost).
    @ObservationIgnored private let persistUsage: (Int, Double) -> Void
    /// Appends one finished turn's activity to the per-chat device-local history.
    @ObservationIgnored private let persistActivity: (TurnActivity) -> Void
    /// Monotonic turn counter for the history records.
    @ObservationIgnored private var turnIndexCounter = 0
    /// Last time we flushed the transcript mid-stream (throttles disk writes).
    @ObservationIgnored private var lastStreamPersist = Date.distantPast

    init(config: Configuration,
         binary: String,
         providerBinaries: [AIProvider: String] = [:],
         providerAPIKeys: [AIProvider: String] = [:],
         codexReasoningEffort: String = "",
         permissionMode: String = "acceptEdits",
         persist: @escaping ([ChatMessage]) -> Void = { _ in },
         onFirstUserMessage: @escaping (String) -> Void = { _ in },
         autoRecommendStrategy: @escaping (String) async -> Strategy? = { _ in nil },
         ensureStrategyFiles: @escaping () -> Void = {},
         persistUsage: @escaping (Int, Double) -> Void = { _, _ in },
         persistActivity: @escaping (TurnActivity) -> Void = { _ in },
         initialHistory: [TurnActivity] = []) {
        self.config = config
        self.binary = binary
        self.providerBinaries = providerBinaries
        self.providerAPIKeys = providerAPIKeys
        self.codexReasoningEffort = codexReasoningEffort
        self.permissionMode = permissionMode
        self.persist = persist
        self.onFirstUserMessage = onFirstUserMessage
        self.autoRecommendStrategy = autoRecommendStrategy
        self.ensureStrategyFiles = ensureStrategyFiles
        self.persistUsage = persistUsage
        self.persistActivity = persistActivity
        self.history = initialHistory
        // Rehydrate the produced-files list from persisted history so files the agents
        // generated in past turns stay listed (and downloadable) when the chat reopens.
        var seenFiles = Set<String>()
        self.editedFiles = initialHistory.flatMap(\.files).filter { seenFiles.insert($0).inserted }
        self.turnIndexCounter = (initialHistory.last?.turnIndex ?? -1) + 1
        self.messages = config.transcript
        self.input = config.draft   // restore unsent text
        self.totalTokens = config.totalTokens
        self.totalCostUSD = config.totalCostUSD
        // A prior transcript implies the repo already has a Claude Code session.
        self.hasSession = !config.transcript.isEmpty
    }

    /// Capture the just-finished turn into the persisted history, then reset the live
    /// per-turn activity. Called at turn END (so the last turn survives relaunch) with
    /// the turn's prompt and the tokens/cost it consumed.
    private func snapshotTurn(prompt: String, tokens: Int, cost: Double) {
        guard !timeline.isEmpty || !commandLog.isEmpty || !tokensByModel.isEmpty
                || !turnEditedFiles.isEmpty else { return }
        let byModel = tokensByModel
            .map { ModelSpend(model: $0.key, tokens: $0.value,
                              costUSD: tokens > 0 ? cost * Double($0.value) / Double(tokens) : 0) }
            .sorted { $0.tokens > $1.tokens }
        let turn = TurnActivity(
            turnIndex: turnIndexCounter, prompt: prompt,
            startedAt: turnStartedAt ?? Date(), endedAt: Date(),
            steps: timeline, agentsInvolved: agentsInvolved, commandLog: commandLog,
            tokensUsed: tokens, costUSD: cost, byModel: byModel, byAgent: tokensByAgent,
            skillsUsed: turnSkillsUsed, files: turnEditedFiles)
        turnIndexCounter += 1
        history.append(turn)
        if history.count > 50 { history = Array(history.suffix(50)) }
        persistActivity(turn)
    }

    deinit {
        // If the chat is torn down mid-run, stop the subprocess/stream.
        runTask?.cancel()
        narrationTicker?.cancel()
    }

    /// Orchestrator (session) model — the launch model, per Claude Code's rules.
    var model: String { config.strategy.orchestrator?.model.rawValue ?? "claude-fable-5" }

    /// Real progress signal for the current turn: the agent's own task list
    /// (TodoWrite). nil until the agent plans tasks — then done/total is genuine.
    var taskProgress: (done: Int, total: Int)? {
        guard !todos.isEmpty else { return nil }
        return (todos.filter { $0.status == "completed" }.count, todos.count)
    }
    /// Whether the last/most-recent turn produced any completed work to mark as done.
    var hasFinishedActivity: Bool { !isRunning && !timeline.isEmpty }
    var canSend: Bool {
        let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachments.isEmpty) && !isRunning
    }

    /// There's something in the composer to submit (text or attachments), whether or
    /// not a turn is running — running turns queue it instead of sending immediately.
    var hasComposerContent: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    /// The composer's primary action. Sends now when idle; otherwise queues the message
    /// and clears the composer, so the user can keep typing ahead (Claude Code-style).
    func submit() {
        guard hasComposerContent else { return }
        guard isRunning else { send(); return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        queued.append(QueuedMessage(text: text, attachments: attachments))
        input = ""
        attachments = []
    }

    /// Remove a queued message before it gets sent.
    func removeQueued(_ id: QueuedMessage.ID) {
        queued.removeAll { $0.id == id }
    }

    /// If the run is idle and messages are waiting, send the next one. Called at the end
    /// of every finished turn so the queue drains one message per turn, in order.
    private func flushQueue() {
        guard !isRunning, !queued.isEmpty else { return }
        let next = queued.removeFirst()
        input = next.text
        attachments = next.attachments
        send()
    }

    /// The folder Claude runs in: the chosen repo, or a per-chat scratch folder so
    /// questions / document reviews work without picking a project.
    private func workingDirectory() -> String {
        if let repo = config.repoPath, !repo.isEmpty { return repo }
        let dir = AppPaths.supportDirectory()
            .appendingPathComponent("sessions/\(config.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// True when the team can't run as a plain Claude Code session — either it mixes
    /// providers or its orchestrator isn't Claude. These runs go through our own
    /// cross-provider MetaOrchestrator instead of ClaudeRunner (Level 2).
    var usesMetaOrchestrator: Bool {
        let providers = Set(config.strategy.roles.map(\.provider))
        let orch = config.strategy.orchestrator?.provider ?? .claude
        return providers.count > 1 || orch != .claude
    }

    /// The chat's bound project folder is set but no longer exists on disk (moved or
    /// deleted after it was picked) — we can't run there and must say so clearly.
    var repoFolderMissing: Bool {
        guard let repo = config.repoPath, !repo.isEmpty else { return false }
        var isDir: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue)
    }

    /// Truncate the transcript to *before* `index` (dropping that message and every
    /// later one) and start a fresh CLI session, so the next send re-runs the
    /// conversation from that point — the basis for edit & regenerate.
    func truncate(from index: Int) {
        guard !isRunning, messages.indices.contains(index) else { return }
        messages.removeSubrange(index...)
        hasSession = false
        persist(messages)
    }

    /// Clear the visible conversation and start a fresh CLI session next turn (/clear).
    func clearTranscript() {
        guard !isRunning else { return }
        messages = []
        hasSession = false
        persist(messages)
    }

    func send() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning else { return }
        // Fail clearly if the chosen project folder was moved/deleted, instead of
        // spawning the CLI in a missing directory and getting a cryptic error.
        if repoFolderMissing {
            errorText = "The project folder for this chat is missing (moved or deleted). Pick it again in Setup."
            return
        }
        // Allow sending attachments alone with a sensible default ask.
        if text.isEmpty, !attachments.isEmpty { text = "Please review the attached files." }
        guard !text.isEmpty else { return }
        // A single-provider Claude team runs as a native Claude Code session; a mixed
        // or non-Claude team runs through our own orchestrator (each role on its CLI).
        let useMeta = usesMetaOrchestrator
        mixedProvidersNote = false
        let repo = workingDirectory()

        // Fold any attached files into the prompt + grant read access to their dirs.
        let atts = attachments
        attachments = []
        let extraDirs = Array(Set(atts.map { $0.url.deletingLastPathComponent().path }))
        lastExtraDirs = extraDirs
        let promptBody: String = atts.isEmpty ? text
            : text + "\n\nAttached files to review:\n" + atts.map { "- \($0.name): \($0.url.path)" }.joined(separator: "\n")
        // Steer reasoning depth by appending the effort directive to the REAL prompt
        // only (never the display text the user sees in the transcript).
        let promptText = promptBody + effort.promptDirective
        lastPromptText = promptText   // real prompt for allow-and-retry
        let displayText: String = atts.isEmpty ? text
            : text + "\n\n📎 " + atts.map { $0.name }.joined(separator: ", ")

        input = ""
        errorText = nil
        activity = []
        activeSubagent = nil
        agentsInvolved = []
        deniedTools = []
        timeline = []
        todos = []
        commandLog = []
        turnSkillsUsed = []
        turnEditedFiles = []
        tokensByModel = [:]
        tokensByAgent = [:]
        roleModels = [:]
        rolesInProgress = []
        roleTasks = [:]
        roleStartedAt = [:]
        pendingCommands = [:]
        turnStartedAt = Date()
        lastStreamPersist = .distantPast
        runTask?.cancel()   // never leave a prior run's subprocess orphaned
        if messages.isEmpty {
            // First turn on an "auto" chat: recommend a team from the prompt with the
            // on-device model (async, free, private) BEFORE the run, so the very first
            // turn already uses the fitting team. `autoRecommendStrategy` returns nil
            // instantly when the user already chose a team, so established chats aren't
            // delayed. isRunning locks the composer while we (briefly) decide.
            isRunning = true
            let firstText = text
            // Track this in runTask so stop() can cancel the (brief) recommend step too —
            // otherwise hitting stop during it would still fire the full run afterward.
            runTask = Task { [weak self] in
                guard let self else { return }
                let recommended = await self.autoRecommendStrategy(firstText)
                if Task.isCancelled { self.isRunning = false; return }
                if let recommended { self.config.strategy = recommended }
                self.onFirstUserMessage(firstText)   // auto-title the chat
                self.commitAndRun(promptText: promptText, displayText: displayText,
                                  repo: repo, useMeta: useMeta, extraDirs: extraDirs)
            }
            return
        }
        commitAndRun(promptText: promptText, displayText: displayText,
                     repo: repo, useMeta: useMeta, extraDirs: extraDirs)
    }

    /// Write the team files, append the turn, and launch the run. Split out of `send`
    /// so the first turn can first `await` an on-device team recommendation.
    private func commitAndRun(promptText: String, displayText: String,
                              repo: String, useMeta: Bool, extraDirs: [String]) {
        // Put the strategy's .claude files in the working folder so the team applies.
        if config.repoPath?.isEmpty ?? true {
            try? StrategyWriter(repoURL: URL(fileURLWithPath: repo), binary: binary)
                .write(strategy: config.strategy)
        } else {
            ensureStrategyFiles()
        }
        messages.append(ChatMessage(role: .user, text: displayText))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isRunning = true
        let resume = hasSession
        persist(messages) // save the question immediately, before the (long) run

        let sessionID = config.id.uuidString.lowercased()
        // Elevate the whole turn if the user chose "always allow" earlier.
        let effectiveMode = elevatedPermissions ? "bypassPermissions" : permissionMode
        let agents = config.strategy.roles.count
        let providerName = config.provider.rawValue
        let startTokens = totalTokens, startCost = totalCostUSD
        Analytics.log(.runStarted(provider: providerName, agents: agents, meta: useMeta))
        runTask = Task { [binary, model, useMeta] in
            if useMeta {
                // Cross-provider run: our orchestrator drives each role's CLI.
                await runMetaTurn(task: promptText, repo: repo, assistantIndex: assistantIndex)
            } else {
                // Try to resume; if the CLI has no session with this id (e.g. a chat
                // from before per-chat sessions existed), start fresh once, invisibly.
                var missing = await runTurn(text: promptText, repo: repo, sessionID: sessionID,
                                            resume: resume, assistantIndex: assistantIndex,
                                            binary: binary, model: model, permissionMode: effectiveMode,
                                            extraDirs: extraDirs)
                if missing, resume {
                    if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = "" }
                    activity = []; activeSubagent = nil
                    missing = await runTurn(text: promptText, repo: repo, sessionID: sessionID,
                                            resume: false, assistantIndex: assistantIndex,
                                            binary: binary, model: model, permissionMode: effectiveMode,
                                            extraDirs: extraDirs)
                }
            }
            isRunning = false
            hasSession = true
            Analytics.log(.runFinished(provider: providerName, agents: agents,
                                       tokens: totalTokens - startTokens,
                                       costCents: Int(((totalCostUSD - startCost) * 100).rounded()),
                                       meta: useMeta))
            // Persist this turn's agent activity to the per-chat history (#7).
            snapshotTurn(prompt: displayText, tokens: totalTokens - startTokens,
                         cost: totalCostUSD - startCost)
            // Drop the assistant placeholder if nothing came back (e.g. it errored).
            if messages.indices.contains(assistantIndex), messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            persist(messages)
            // Send the next queued message (if any) now that the run is free.
            flushQueue()
        }
    }

    /// Run one streamed turn into `assistantIndex`. Returns true if it failed
    /// specifically because the CLI session was missing (so the caller can retry fresh).
    private func runTurn(text: String, repo: String, sessionID: String, resume: Bool,
                         assistantIndex: Int, binary: String, model: String,
                         permissionMode: String, extraDirs: [String] = []) async -> Bool {
        var gotDelta = false          // did live streaming deliver text this turn?
        var separatorPending = false  // insert a blank line before the next text
        var sessionMissing = false
        // "Ask" mode drives the run via stream-json input so the CLI can request
        // per-tool permission live; every other mode uses the proven -p path.
        let stream: AsyncStream<ChatEvent>
        if permissionMode == "ask" {
            let responder = PermissionResponder()
            permissionResponder = responder
            stream = ClaudeRunner.streamAsking(binary: binary, repoPath: repo, prompt: text,
                                               model: model, sessionID: sessionID, resume: resume,
                                               extraDirs: extraDirs, responder: responder)
        } else {
            stream = ClaudeRunner.stream(binary: binary, repoPath: repo, prompt: text, model: model,
                                         sessionID: sessionID, resume: resume,
                                         permissionMode: permissionMode, extraDirs: extraDirs)
        }
        for await event in stream {
            guard messages.indices.contains(assistantIndex) else { continue }
            switch event {
            case .assistantDelta(let chunk):
                gotDelta = true
                if separatorPending, !messages[assistantIndex].text.isEmpty {
                    messages[assistantIndex].text += "\n\n"
                }
                separatorPending = false
                messages[assistantIndex].text += chunk
                persistStreaming()
            case .assistantText(let chunk):
                guard !gotDelta else { break }
                if !messages[assistantIndex].text.isEmpty {
                    messages[assistantIndex].text += "\n\n"
                }
                messages[assistantIndex].text += chunk
                persistStreaming()
            case .tool(let name, let detail):
                activity.append(name)
                timeline.append(ActivityStep(title: name, detail: detail, at: Date(),
                                             isDelegation: false, agent: activeSubagent))
                separatorPending = true
            case .delegated(let subagent):
                activeSubagent = subagent
                if !agentsInvolved.contains(subagent) { agentsInvolved.append(subagent) }
                activity.append("→ \(subagent)")
                // The delegation itself is an orchestrator action (agent: nil).
                timeline.append(ActivityStep(title: subagent, detail: nil, at: Date(),
                                             isDelegation: true, agent: nil))
                separatorPending = true
            case .commandStarted(let id, let command):
                pendingCommands[id] = command
            case .commandOutput(let id, let output):
                // Only surface output for commands we tracked (Bash), not every tool.
                if let cmd = pendingCommands[id] {
                    commandLog.append(CommandRun(command: cmd, output: output, at: Date()))
                    pendingCommands[id] = nil
                }
            case .todos(let items):
                todos = items
            case .fileEdited(let path):
                if !editedFiles.contains(path) { editedFiles.append(path) }
                if !turnEditedFiles.contains(path) { turnEditedFiles.append(path) }
            case .skillUsed(let slug):
                if !turnSkillsUsed.contains(slug) { turnSkillsUsed.append(slug) }
                if !skillsUsed.contains(slug) { skillsUsed.append(slug) }
                activity.append("skill: \(slug)")
                timeline.append(ActivityStep(title: "Skill", detail: slug, at: Date(),
                                             isDelegation: false, agent: activeSubagent))
                separatorPending = true
            case .denied(let items):
                deniedTools = items
            case .usage(let tokens, let cost):
                totalTokens += tokens
                totalCostUSD += cost
                persistUsage(totalTokens, totalCostUSD)
            case .modelUsage(let model, let tokens):
                // Exact per-model split; attribute to the active subagent too (native
                // best-effort — subagent messages carry their own model when inlined).
                tokensByModel[model, default: 0] += tokens
                if let sub = activeSubagent { tokensByAgent[sub, default: 0] += tokens }
            case .permissionRequest(let id, let tool, let detail):
                // Surface the live approval gate — the run pauses until the user answers.
                pendingPermission = PendingPermission(id: id, toolName: tool, detail: detail)
            case .finished:
                pendingPermission = nil
                break
            case .failed(let message):
                if resume, message.localizedCaseInsensitiveContains("No conversation found") {
                    sessionMissing = true   // retry fresh, don't surface
                } else {
                    DiagnosticsLog.record(message)
                    errorText = message
                }
            }
        }
        return sessionMissing
    }

    /// Run one turn through the cross-provider MetaOrchestrator: it plans on the
    /// orchestrator's model, delegates each subtask to its role's provider/model,
    /// and synthesizes a final answer. Events are bridged to an ordered stream so
    /// UI state mutates on the main actor.
    private func runMetaTurn(task: String, repo: String, assistantIndex: Int) async {
        // Give the runner every configured provider binary (not just Claude), so a
        // Codex/Gemini role resolves via the same path that marked it connected —
        // otherwise the first mixed-provider turn fails with "CLI isn't installed".
        var binaries = providerBinaries
        binaries[.claude] = binary
        let runner = CLIOneShotRunner(binaries: binaries, permissionMode: permissionMode,
                                      apiKeys: providerAPIKeys, reasoningEffort: codexReasoningEffort)
        let strategy = config.strategy
        metaNarration = []
        narrationStepSince = nil
        // Heartbeat: the workers/synthesis are one-shot CLIs with no token streaming, so
        // between step transitions the bubble would sit still for minutes. Re-render once
        // a second to keep the active step's elapsed timer visibly ticking ("…en directo").
        narrationTicker?.cancel()
        narrationTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.renderNarration(assistantIndex)
            }
        }
        // The meta path is stateless (each role is a one-shot CLI with no session), so —
        // unlike the native Claude path with --session-id — follow-up turns would lose all
        // prior context. Prepend the recent conversation so the team continues the thread.
        let contextualTask = metaTaskWithContext(task, upTo: assistantIndex)
        let stream = AsyncStream<MetaEvent> { cont in
            let task = Task.detached {
                await MetaOrchestrator.run(strategy: strategy, task: contextualTask, cwd: repo, runner: runner) {
                    cont.yield($0)
                }
                cont.finish()
            }
            // Cancelling the turn (stop / teardown) must cancel the orchestrator so
            // its running CLIs are terminated instead of burning tokens in the dark.
            cont.onTermination = { _ in task.cancel() }
        }
        for await event in stream {
            apply(event, assistantIndex: assistantIndex)
        }
        narrationTicker?.cancel()
        narrationTicker = nil
    }

    /// Prepend the recent conversation to a meta-turn task so the cross-provider team has
    /// the same running context a normal Claude/ChatGPT chat keeps. The native path gets
    /// this for free via `--session-id`; the meta path must carry it in the prompt. Recent
    /// history is included within a character budget so the prompt stays bounded.
    private func metaTaskWithContext(_ current: String, upTo index: Int) -> String {
        // Everything before the current user message + the empty assistant placeholder.
        let prior = Array(messages.prefix(max(0, index - 1)))
        guard !prior.isEmpty else { return current }
        var budget = 12_000
        var lines: [String] = []
        for m in prior.reversed() where !m.text.isEmpty {
            let line = "\(m.role == .user ? "User" : "Assistant"): \(m.text)"
            if line.count > budget { break }
            budget -= line.count
            lines.append(line)
        }
        guard !lines.isEmpty else { return current }
        return """
        CONVERSATION SO FAR (context — continue this thread, do not restart):
        \(lines.reversed().joined(separator: "\n\n"))

        CURRENT REQUEST:
        \(current)
        """
    }

    /// Map a MetaOrchestrator event onto the same chat/activity state the Claude
    /// path uses, so the activity panel and transcript work identically.
    private func apply(_ event: MetaEvent, assistantIndex: Int) {
        let orchName = config.strategy.orchestrator?.name
        switch event {
        case .phase(let p):
            activity.append(p)
            if p != "delegate" { activeSubagent = nil }   // orchestrator is planning/synthesizing
            narrate(phaseNarration(p), assistantIndex: assistantIndex)
        case .roleStarted(let role, _, let model, let task):
            if role == orchName {
                activeSubagent = nil
            } else {
                activeSubagent = role
                rolesInProgress.insert(role)
                roleModels[role] = model
                let brief = task.trimmingCharacters(in: .whitespacesAndNewlines)
                if !brief.isEmpty { roleTasks[role] = brief }
                if !agentsInvolved.contains(role) { agentsInvolved.append(role) }
                activity.append("→ \(role)")
                roleStartedAt[role] = Date()
                // The step DETAIL now carries the assigned task, so the timeline shows
                // what each agent is actually doing — not just that it was delegated to.
                timeline.append(ActivityStep(title: role, detail: shortTask(brief) ?? model, at: Date(),
                                             isDelegation: true, agent: nil))
                // A step attributed to the AGENT itself, so its per-agent drill-down shows
                // "working on …" the moment it starts — instead of staying empty for the
                // minutes the one-shot CLI runs with no intermediate output.
                timeline.append(ActivityStep(title: "role.working", detail: shortTask(brief) ?? model,
                                             at: Date(), isDelegation: false, agent: role))
                let taskSuffix = shortTask(brief).map { " — \($0)" } ?? ""
                narrate("▸ \(role) · \(model)\(taskSuffix)…", assistantIndex: assistantIndex)
            }
        case .roleFinished(let role, let tokens):
            // Exact per-agent + per-model attribution on the cross-provider path.
            if tokens > 0 {
                tokensByAgent[role, default: 0] += tokens
                if let m = roleModels[role] { tokensByModel[m, default: 0] += tokens }
            }
            if role != orchName {
                rolesInProgress.remove(role)
                roleStartedAt[role] = nil
                // Attribute a completed step to the agent so the panel marks it done.
                timeline.append(ActivityStep(title: "role.done", detail: role, at: Date(),
                                             isDelegation: false, agent: role))
                markNarrationDone(role, assistantIndex: assistantIndex)
            }
        case .roleFailed(let role, let message):
            // One worker failed but the run continues with the others — record it and
            // mark this agent's narration line as failed so the UI isn't left "working".
            rolesInProgress.remove(role)
            roleStartedAt[role] = nil
            DiagnosticsLog.record("meta worker “\(role)” failed — \(message)")
            if let i = metaNarration.lastIndex(where: { $0.contains(role) && $0.hasPrefix("▸") }) {
                metaNarration[i] = "⚠ \(role)"
                narrationStepSince = Date()
                renderNarration(assistantIndex)
            }
            timeline.append(ActivityStep(title: "role.failed", detail: role, at: Date(),
                                         isDelegation: false, agent: role))
        case .assistantText(let text):
            // The final synthesis replaces the live narration. The answer stays in the
            // transcript only — it is NOT written to disk as a file (a plain response is
            // not a "download"; only real files the agents write with tools are listed).
            metaNarration = []
            narrationStepSince = nil
            if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = text }
            persistStreaming()
        case .usage(let tokens, let cost):
            totalTokens += tokens
            totalCostUSD += cost
            persistUsage(totalTokens, totalCostUSD)
        case .failed(let message):
            DiagnosticsLog.record(message)
            errorText = message
            rolesInProgress = []
            roleStartedAt = [:]
        case .finished:
            activeSubagent = nil
            rolesInProgress = []   // nothing is in flight once the run finishes
            roleStartedAt = [:]
        }
    }

    // MARK: - Meta live narration

    private var narrationLang: String { (Locale.preferredLanguages.first?.hasPrefix("es") == true) ? "es" : "en" }

    private func phaseNarration(_ p: String) -> String {
        switch p {
        case "plan":      return L10n.string("meta.narrate.plan", langCode: narrationLang)
        case "delegate":  return L10n.string("meta.narrate.delegate", langCode: narrationLang)
        default:          return L10n.string("meta.narrate.synthesize", langCode: narrationLang)
        }
    }

    /// Append a line to the live narration and render it into the assistant bubble.
    private func narrate(_ line: String, assistantIndex: Int) {
        metaNarration.append(line)
        narrationStepSince = Date()   // start the elapsed clock for this step
        renderNarration(assistantIndex)
    }

    /// Flip a role's "▸ … working" line to "✓ done" once it finishes.
    private func markNarrationDone(_ role: String, assistantIndex: Int) {
        if let i = metaNarration.lastIndex(where: { $0.contains(role) && $0.hasPrefix("▸") }) {
            metaNarration[i] = "✓ \(role)"
            narrationStepSince = Date()   // reset the clock for whatever runs next
            renderNarration(assistantIndex)
        }
    }

    private func renderNarration(_ assistantIndex: Int) {
        guard messages.indices.contains(assistantIndex), !metaNarration.isEmpty else { return }
        var lines = metaNarration
        // Tick a live elapsed timer onto the current in-progress step (a line ending in
        // "…"), so the bubble keeps moving during the minutes-long one-shot calls.
        if let since = narrationStepSince, let last = lines.indices.last,
           lines[last].hasSuffix("…") {
            let secs = Int(Date().timeIntervalSince(since))
            if secs >= 2 { lines[last] += "  ·  \(narrationElapsed(secs))" }
        }
        messages[assistantIndex].text = lines.joined(separator: "\n")
    }

    /// "45s" / "2m 03s" for the live step timer.
    private func narrationElapsed(_ secs: Int) -> String {
        secs < 60 ? "\(secs)s" : "\(secs / 60)m \(String(format: "%02d", secs % 60))s"
    }

    /// A one-line, trimmed excerpt of an assigned task for the narration/timeline, so the
    /// UI shows what an agent is doing without dumping a paragraph. nil when empty.
    private func shortTask(_ task: String) -> String? {
        let firstLine = task.split(separator: "\n").first.map(String.init) ?? task
        let clean = firstLine.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        return clean.count > 80 ? String(clean.prefix(79)) + "…" : clean
    }

    /// Flush the transcript to disk at most every ~1.5s during streaming, so a
    /// crash mid-reply doesn't lose the whole response (the full flush still
    /// happens when the turn ends).
    private func persistStreaming() {
        let now = Date()
        guard now.timeIntervalSince(lastStreamPersist) > 1.5 else { return }
        lastStreamPersist = now
        persist(messages)
    }

    /// Re-run the last user message granting full permissions — the "allow & retry"
    /// path when a run was blocked by permission denials. Works with or without a
    /// project folder (scratch sessions use their per-chat folder).
    /// Turn OFF the persistent "full access" elevation for this chat.
    func disableElevation() { elevatedPermissions = false }

    func retryAllowingAll(persistElevation: Bool = false) {
        if persistElevation { elevatedPermissions = true }
        // Reuse the REAL last prompt (with file paths), not the display text.
        let prompt = lastPromptText.isEmpty
            ? (messages.last(where: { $0.role == .user })?.text ?? "")
            : lastPromptText
        guard !isRunning, !prompt.isEmpty else { return }
        let repo = workingDirectory()
        deniedTools = []; errorText = nil; activity = []; activeSubagent = nil
        agentsInvolved = []; timeline = []; todos = []; turnStartedAt = Date()
        turnSkillsUsed = []
        turnEditedFiles = []
        rolesInProgress = []; roleTasks = [:]
        commandLog = []; pendingCommands = [:]; tokensByModel = [:]; tokensByAgent = [:]; roleModels = [:]
        lastStreamPersist = .distantPast
        runTask?.cancel()   // don't orphan a prior run
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isRunning = true
        persist(messages)
        let sessionID = config.id.uuidString.lowercased()
        let useMeta = usesMetaOrchestrator
        let startTokens = totalTokens, startCost = totalCostUSD
        runTask = Task { [binary, model, useMeta] in
            if useMeta {
                // Cross-provider runs are one-shot; permissions don't apply — just re-run.
                await runMetaTurn(task: prompt, repo: repo, assistantIndex: assistantIndex)
            } else {
                // Resume with full permissions; fall back to a fresh session if the CLI
                // has no record of this one (mirrors send()).
                var missing = await runTurn(text: prompt, repo: repo, sessionID: sessionID, resume: true,
                                            assistantIndex: assistantIndex, binary: binary, model: model,
                                            permissionMode: "bypassPermissions", extraDirs: lastExtraDirs)
                if missing {
                    if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = "" }
                    activity = []; activeSubagent = nil
                    missing = await runTurn(text: prompt, repo: repo, sessionID: sessionID, resume: false,
                                            assistantIndex: assistantIndex, binary: binary, model: model,
                                            permissionMode: "bypassPermissions", extraDirs: lastExtraDirs)
                }
            }
            isRunning = false
            hasSession = true
            snapshotTurn(prompt: prompt, tokens: totalTokens - startTokens,
                         cost: totalCostUSD - startCost)
            if messages.indices.contains(assistantIndex), messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            persist(messages)
            flushQueue()
        }
    }

    /// Answer the live permission gate ("Ask" mode); the run resumes or the tool is
    /// skipped. `always` marks the whole rest of this chat as auto-allowed.
    func respondPermission(_ id: String, allow: Bool, always: Bool = false) {
        permissionResponder?.respond(id: id, allow: allow)
        if always { elevatedPermissions = true }
        pendingPermission = nil
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        pendingPermission = nil
        // Interrupting the run also drops anything queued behind it — the user hit stop,
        // so don't quietly fire off the messages they'd lined up.
        queued = []
        Analytics.log(.runCancelled)
    }
}
