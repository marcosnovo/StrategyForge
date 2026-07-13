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
    var labelKey: String { "effort.\(rawValue)" }
    var blurbKey: String { "effort.\(rawValue).blurb" }
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

/// One entry in the live agent-activity timeline.
struct ActivityStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String?
    let at: Date
    let isDelegation: Bool
    /// Which agent performed this step — nil means the orchestrator. Used to
    /// attribute steps to a subagent for the per-agent drill-down.
    var agent: String? = nil
}

/// One shell command the agent ran, with its output (for the code-mode terminal).
struct CommandRun: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let output: String
    let at: Date
}

/// A staged attachment: the name shown to the user and the (possibly converted)
/// file Claude actually reads.
struct Attachment: Identifiable, Hashable {
    let id = UUID()
    let name: String   // original file name (for display)
    let url: URL       // file to hand to Claude (original or converted .txt)
}

@Observable
@MainActor
final class ChatViewModel {
    /// AppModel refreshes it on lookup; views must not write.
    var config: Configuration
    private let binary: String

    var messages: [ChatMessage] = []
    /// Tools the agent used during the current turn (shown as a status line).
    var activity: [String] = []
    /// Absolute paths of files the agent has written/edited in this chat.
    var editedFiles: [String] = []
    /// The subagent the orchestrator is currently delegating to (if any).
    var activeSubagent: String?
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
    /// Bash tool_use id → command, to pair output (tool_result) back to its command.
    @ObservationIgnored private var pendingCommands: [String: String] = [:]
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
    /// Last time we flushed the transcript mid-stream (throttles disk writes).
    @ObservationIgnored private var lastStreamPersist = Date.distantPast

    init(config: Configuration,
         binary: String,
         permissionMode: String = "acceptEdits",
         persist: @escaping ([ChatMessage]) -> Void = { _ in },
         onFirstUserMessage: @escaping (String) -> Void = { _ in },
         autoRecommendStrategy: @escaping (String) async -> Strategy? = { _ in nil },
         ensureStrategyFiles: @escaping () -> Void = {},
         persistUsage: @escaping (Int, Double) -> Void = { _, _ in }) {
        self.config = config
        self.binary = binary
        self.permissionMode = permissionMode
        self.persist = persist
        self.onFirstUserMessage = onFirstUserMessage
        self.autoRecommendStrategy = autoRecommendStrategy
        self.ensureStrategyFiles = ensureStrategyFiles
        self.persistUsage = persistUsage
        self.messages = config.transcript
        self.input = config.draft   // restore unsent text
        self.totalTokens = config.totalTokens
        self.totalCostUSD = config.totalCostUSD
        // A prior transcript implies the repo already has a Claude Code session.
        self.hasSession = !config.transcript.isEmpty
    }

    deinit {
        // If the chat is torn down mid-run, stop the subprocess/stream.
        runTask?.cancel()
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
            Task { [weak self] in
                guard let self else { return }
                if let recommended = await self.autoRecommendStrategy(firstText) {
                    self.config.strategy = recommended
                }
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
            // Drop the assistant placeholder if nothing came back (e.g. it errored).
            if messages.indices.contains(assistantIndex), messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            persist(messages)
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
        for await event in ClaudeRunner.stream(binary: binary, repoPath: repo,
                                               prompt: text, model: model,
                                               sessionID: sessionID, resume: resume,
                                               permissionMode: permissionMode, extraDirs: extraDirs) {
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
            case .denied(let items):
                deniedTools = items
            case .usage(let tokens, let cost):
                totalTokens += tokens
                totalCostUSD += cost
                persistUsage(totalTokens, totalCostUSD)
            case .finished:
                break
            case .failed(let message):
                if resume, message.localizedCaseInsensitiveContains("No conversation found") {
                    sessionMissing = true   // retry fresh, don't surface
                } else {
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
        let runner = CLIOneShotRunner(binaries: [.claude: binary], permissionMode: permissionMode)
        let strategy = config.strategy
        let stream = AsyncStream<MetaEvent> { cont in
            let task = Task.detached {
                await MetaOrchestrator.run(strategy: strategy, task: task, cwd: repo, runner: runner) {
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
    }

    /// Map a MetaOrchestrator event onto the same chat/activity state the Claude
    /// path uses, so the activity panel and transcript work identically.
    private func apply(_ event: MetaEvent, assistantIndex: Int) {
        let orchName = config.strategy.orchestrator?.name
        switch event {
        case .phase(let p):
            activity.append(p)
            if p != "delegate" { activeSubagent = nil }   // orchestrator is planning/synthesizing
        case .roleStarted(let role, _, let model):
            if role == orchName {
                activeSubagent = nil
            } else {
                activeSubagent = role
                if !agentsInvolved.contains(role) { agentsInvolved.append(role) }
                activity.append("→ \(role)")
                timeline.append(ActivityStep(title: role, detail: model, at: Date(),
                                             isDelegation: true, agent: nil))
            }
        case .roleFinished(let role, _):
            if role != orchName {
                // Attribute a completed step to the agent so the panel marks it done.
                timeline.append(ActivityStep(title: "done", detail: nil, at: Date(),
                                             isDelegation: false, agent: role))
            }
        case .assistantText(let text):
            if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = text }
            persistStreaming()
        case .usage(let tokens, let cost):
            totalTokens += tokens
            totalCostUSD += cost
            persistUsage(totalTokens, totalCostUSD)
        case .failed(let message):
            errorText = message
        case .finished:
            break
        }
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
        commandLog = []; pendingCommands = [:]
        lastStreamPersist = .distantPast
        runTask?.cancel()   // don't orphan a prior run
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isRunning = true
        persist(messages)
        let sessionID = config.id.uuidString.lowercased()
        let useMeta = usesMetaOrchestrator
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
            if messages.indices.contains(assistantIndex), messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            persist(messages)
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        Analytics.log(.runCancelled)
    }
}
