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

/// The infrastructure settings a run reads FRESH each turn — CLI binary paths, API
/// keys, Codex effort — so changing them in Settings takes effect in an already-open
/// chat instead of being frozen at the VM's creation (a cached VM lives for the whole
/// session). See ChatViewModel.liveSettings.
struct ChatRunSettings {
    var claudeBinary: String
    var providerBinaries: [AIProvider: String]
    var providerAPIKeys: [AIProvider: String]
    var codexReasoningEffort: String
}

@Observable
@MainActor
final class ChatViewModel {
    /// AppModel refreshes it on lookup; views must not write.
    var config: Configuration
    /// Reads the current run settings each turn (nil in previews → use the snapshot the
    /// init captured). This is what makes a Settings change reach an open chat.
    @ObservationIgnored private let liveSettings: (() -> ChatRunSettings)?
    @ObservationIgnored private let snapshotBinary: String
    @ObservationIgnored private let snapshotProviderBinaries: [AIProvider: String]
    @ObservationIgnored private let snapshotProviderAPIKeys: [AIProvider: String]
    @ObservationIgnored private let snapshotCodexEffort: String

    /// The Claude CLI path — live from Settings when available, else the init snapshot.
    private var binary: String { liveSettings?().claudeBinary ?? snapshotBinary }
    /// Configured CLI binaries per provider (from AppSettings), so a cross-provider
    /// meta run can resolve Codex/Gemini via the same paths that marked them
    /// connected. Empty in previews → the meta run uses just the Claude binary.
    private var providerBinaries: [AIProvider: String] {
        liveSettings?().providerBinaries ?? snapshotProviderBinaries
    }
    /// Optional per-provider API keys (OpenAI) so a cross-provider meta run can use
    /// the API (which re-enables model selection) instead of the subscription default.
    private var providerAPIKeys: [AIProvider: String] {
        liveSettings?().providerAPIKeys ?? snapshotProviderAPIKeys
    }
    /// Codex reasoning effort ("" = account default), passed to the meta runner.
    private var codexReasoningEffort: String {
        liveSettings?().codexReasoningEffort ?? snapshotCodexEffort
    }

    var messages: [ChatMessage] = []
    /// Tools the agent used during the current turn (shown as a status line).
    var activity: [String] = []
    /// Absolute paths of files the agent has written/edited in this chat.
    var editedFiles: [String] = []
    /// Per-file authorship (abs path → the team member that last edited it), so Code
    /// mode's changed-files list shows which agent/model wrote each file — the "mix
    /// providers per role" payoff made auditable. Live/transient (not persisted).
    var fileProvenance: [String: EditProvenance] = [:]
    /// Per-LINE authorship (abs path → author per new-file line, 0-based), so the diff can
    /// tint each line by who wrote it. Built by snapshot-diffing the file on each edit.
    var lineProvenance: [String: [EditProvenance?]] = [:]
    /// The last content we saw for each edited file, to diff the next edit against.
    @ObservationIgnored private var fileSnapshots: [String: [String]] = [:]
    /// MRU order of paths tracked in `fileSnapshots`/`lineProvenance`, so we can cap how many
    /// full-file line snapshots stay resident (a big refactor touching 100s of files would
    /// otherwise hold every file's line array in RAM for the chat's whole life).
    @ObservationIgnored private var provenanceOrder: [String] = []
    private static let maxProvenanceFiles = 40
    /// Per-path serial chain so a path's edits are attributed in ORDER even though the read
    /// + diff run off-main (a later edit awaits the earlier one's write before it snapshots).
    @ObservationIgnored private var provenanceChain: [String: Task<Void, Never>] = [:]
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
    /// Meta path: the latest cleaned line of a role's raw output (Codex/Gemini, which have
    /// no structured tool stream) — a rolling "what it's doing right now" shown on the
    /// active agent row so the run never reads as silent/frozen.
    var roleLiveLine: [String: String] = [:]
    /// Meta path: how many INSTANCES of a role are running right now. A role with count>1
    /// (e.g. researcher ×3) fans out to several parallel one-shot calls that all share the
    /// role name; without a count the first to finish would mark the whole role done and
    /// only one would ever look active. Increment on each instance start, decrement on each
    /// finish/fail; the role stays "working" until it hits 0.
    var rolesRunning: [String: Int] = [:]
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
    /// True while fetching a cross-provider second opinion — a separate, additive path that
    /// never touches the main run machinery (own flag, no onRunningChanged side effects).
    var isSecondOpinionRunning = false

    /// Run the last user ask on ANOTHER provider as a one-shot (off the main run path) and
    /// append its answer, labeled with `headerPrefix` — the cross-provider differentiator
    /// made tangible ("get a second opinion from Codex"). User-initiated, so spending is
    /// consented by the tap.
    func secondOpinion(provider: AIProvider, model modelID: String, cwd: String?,
                       runner: OneShotRunner, headerPrefix: String) async {
        guard !isRunning, !isSecondOpinionRunning,
              let ask = messages.last(where: { $0.role == .user })?.text,
              !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSecondOpinionRunning = true
        defer { isSecondOpinionRunning = false }
        let out = (try? await runner.run(prompt: ask, provider: provider, model: modelID, cwd: cwd))?.text ?? ""
        let body = out.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(ChatMessage(role: .assistant, text: headerPrefix + (body.isEmpty ? "—" : body)))
        persist(messages)
    }
    /// Notifies the owner (AppModel) when a turn starts/ends, so global running
    /// indicators and finish banners work even when this chat isn't on screen.
    @ObservationIgnored var onRunningChanged: ((Bool) -> Void)?
    var errorText: String?
    /// A provider whose saved login looks expired (detected mid-run) — the UI shows a
    /// one-tap "Reconnect" banner so a stale session self-heals instead of hanging.
    var needsReauth: AIProvider?
    /// Running token total + cost for this chat, grows per turn.
    var totalTokens = 0
    var totalCostUSD = 0.0
    /// True once any usage in this chat was ESTIMATED (a cross-provider CLI that reports
    /// no real token count — Codex plain output, Gemini), so the UI can prefix cost/tokens
    /// with "~" instead of implying an exact figure.
    var costEstimated = false

    /// Whether a Claude Code session already exists in the repo (→ use `--continue`).
    private var hasSession = false
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// Monotonic run id. Bumped when a run starts; a run's epilogue (unlock, snapshot,
    /// drop-empty-placeholder, flush queue) only fires when its epoch is still current —
    /// so a stop→send race can't let the OLD run's epilogue clobber the NEW run's state
    /// (stale `assistantIndex`, a spurious `isRunning = false`, or a double flush).
    @ObservationIgnored private var runEpoch = 0
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
    /// "Grill me first": when on, the agent interrogates you about edge cases BEFORE doing any
    /// work (the article's /grill-me idea) — front-loading the questions the verifier would
    /// otherwise catch late. Injected as a prompt directive, like effort.
    var grillMe = false
    /// "Propose approaches first" (the article's prototype-first idea): before implementing,
    /// the agent lays out N distinct approaches to compare so you pick before it builds.
    var proposeApproaches = false
    static let approachesDirective = """
        \n\nBEFORE writing any code, propose 3 DISTINCT approaches to this task. For each, give:
        a short name + one-line summary, its main tradeoffs (effort, risk, simplicity,
        extensibility), and when it's the right pick. Present them as a compact side-by-side
        comparison, recommend one with a reason, and WAIT for me to choose before implementing.
        """
    /// The adversarial-planning directive appended when `grillMe` is on.
    static let grillDirective = """
        \n\nBEFORE writing any code or making any changes, STOP and interrogate me. Ask the 3–7
        sharpest clarifying and edge-case questions this task needs answered — inputs and their
        shapes, empty/error/loading states, scope boundaries and explicit non-goals, failure
        modes, and any assumption that would be expensive to get wrong. Number them and WAIT for
        my answers. Do not implement anything until I respond.
        """

    // MARK: - Isolation ("Permissive ⇒ isolate")

    /// A git worktree the run is confined to, so autonomous edits don't touch the live tree
    /// until you review + merge. Reuses the same machinery Arena uses.
    struct IsolationSession: Equatable { let path: String; let branch: String }
    private(set) var isolation: IsolationSession?
    /// A worktree create/merge/teardown is in flight (drives the toggle/banner busy state).
    private(set) var isolationBusy = false

    /// Composer toggle: OFF→ON creates a worktree; ON→(clean) tears it down (a dirty worktree
    /// must be merged or discarded from the banner so work is never silently lost).
    func requestIsolation() {
        guard !isolationBusy else { return }
        if isolation != nil { Task { await self.discardIfClean() }; return }
        guard let repo = config.repoPath, !repo.isEmpty else { return }
        isolationBusy = true
        Task {
            self.isolation = await Self.makeWorktree(repo: repo)
            self.isolationBusy = false
        }
    }

    private static func makeWorktree(repo: String) async -> IsolationSession? {
        let id = UUID().uuidString.prefix(8)
        let branch = "coral/isolated-\(id)"
        let path = AppPaths.supportDirectory()
            .appendingPathComponent("worktrees/\(CodeGit.repoName(from: repo))-\(id)", isDirectory: true).path
        let r = await CodeGit.addWorktree(repo: repo, path: path, branch: branch)
        return r.ok ? IsolationSession(path: path, branch: branch) : nil
    }

    /// The full diff of the isolated work (for the review sheet).
    func isolationDiff() async -> String? {
        guard let iso = isolation else { return nil }
        return await CodeGit.fullDiff(repo: iso.path)
    }

    // MARK: Independent verification (Bet 3 — "autonomous but accountable")

    /// The result of independently verifying the isolated diff before merge.
    private(set) var isolationFindings: [ReviewFinding] = []
    private(set) var isolationVerifiedBy: AIProvider?
    private(set) var isolationVerifyError: String?
    /// The panel of independent judges that graded the diff (different families when possible)
    /// — averaging across families breaks a single judge's correlated bias.
    private(set) var isolationJudges: [AIProvider] = []
    /// The change's blast radius (how expensive a bad merge is to undo) — gate on this, not on
    /// the model's confidence. Irreversible changes must never auto-merge.
    private(set) var isolationBlast: BlastAssessment?

    /// Run an INDEPENDENT read-only review of the isolated diff (reviewer ≠ author — ideally a
    /// DIFFERENT provider family), so autonomous changes are gated by a separate judge before you
    /// merge them. This welds Coral's verifier + isolation + provenance into one accountable step.
    func verifyIsolation() async {
        guard let iso = isolation, !isolationBusy else { return }
        isolationBusy = true
        defer { isolationBusy = false }
        isolationVerifyError = nil
        guard let diff = await CodeGit.fullDiff(repo: iso.path),
              !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isolationFindings = []; isolationVerifiedBy = nil; isolationJudges = []; isolationBlast = nil
            isolationVerifyError = "No changes to verify yet."
            return
        }
        // Gate on BLAST RADIUS (how costly a bad merge is to undo), not the model's confidence.
        isolationBlast = BlastRadiusClassifier.classify(diff: diff)
        // A PANEL of independent judges (different families when connected) — averaging across
        // families breaks a single judge's correlated bias. Falls back to one when only one exists.
        let judges = independentReviewers(max: 3)
        var bins = providerBinaries; bins[.claude] = binary
        let runner = CLIOneShotRunner(binaries: bins, apiKeys: providerAPIKeys,
                                      reasoningEffort: codexReasoningEffort, readOnly: true)
        var perJudge: [[ReviewFinding]] = []
        var ran: [AIProvider] = []
        var lastError: String?
        for judge in judges {
            do {
                let r = try await runner.run(prompt: DiffReviewer.reviewPrompt(diff: diff),
                                             provider: judge, model: "", cwd: iso.path)
                perJudge.append(DiffReviewer.parseFindings(r.text))
                ran.append(judge)
                // Pin/log the judge (family + model returned) so a score is always traceable to
                // exactly which examiner produced it (judges are versioned software).
                DiagnosticsLog.record("verify judge: \(judge.displayName) · model=\(r.model.isEmpty ? "default" : r.model) · findings=\(perJudge.last?.count ?? 0)")
            } catch {
                lastError = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
            }
        }
        guard !ran.isEmpty else {
            isolationFindings = []; isolationVerifiedBy = nil; isolationJudges = []
            isolationVerifyError = lastError ?? "No judge could run."
            return
        }
        isolationFindings = DiffReviewer.combinePanel(perJudge).map(\.finding)
        isolationJudges = ran
        isolationVerifiedBy = ran.first
    }

    /// Up to `max` reviewers of DIFFERENT families than the chat's provider (independent second
    /// opinions), then the author's own family last as a fallback so there's always ≥1.
    private func independentReviewers(max: Int) -> [AIProvider] {
        var out: [AIProvider] = []
        for p in [AIProvider.openai, .gemini, .claude] where p != config.provider {
            if CLIOneShotRunner.resolveBinary(providerBinaries[p] ?? "", provider: p) != nil { out.append(p) }
        }
        if out.isEmpty { out.append(config.provider) }   // still read-only, reviewer≠author
        return Array(out.prefix(Swift.max(1, max)))
    }

    private func clearVerification() {
        isolationFindings = []; isolationVerifiedBy = nil; isolationVerifyError = nil
        isolationJudges = []; isolationBlast = nil
    }

    /// Commit the worktree's changes and merge them (no-ff) into the live tree, then tear down.
    func mergeIsolation() async {
        guard let iso = isolation, let repo = config.repoPath, !isolationBusy else { return }
        isolationBusy = true
        _ = await CodeGit.commitAll(dir: iso.path, message: "Coral: isolated changes")
        let r = await CodeGit.mergeNoFF(repo: repo, branch: iso.branch, message: "Merge Coral isolated run")
        if !r.ok {
            await CodeGit.abortMerge(repo: repo)
            errorText = "Couldn't merge the isolated changes (conflicts). Resolve manually.\n" + r.out
        }
        await teardownWorktree()
        isolationBusy = false
    }

    /// Throw the worktree away without merging.
    func discardIsolation() async {
        guard !isolationBusy else { return }
        isolationBusy = true
        await teardownWorktree()
        isolationBusy = false
    }

    private func discardIfClean() async {
        guard let iso = isolation else { return }
        if await CodeGit.hasUncommittedChanges(repo: iso.path) == false { await teardownWorktree() }
    }
    private func teardownWorktree() async {
        clearVerification()
        guard let iso = isolation, let repo = config.repoPath else { isolation = nil; return }
        await CodeGit.removeWorktree(repo: repo, path: iso.path)
        await CodeGit.deleteBranch(repo: repo, name: iso.branch)
        isolation = nil
    }

    /// Persists cumulative usage (tokens, cost).
    @ObservationIgnored private let persistUsage: (Int, Double) -> Void
    /// Appends one finished turn's activity to the per-chat device-local history.
    @ObservationIgnored private let persistActivity: (TurnActivity) -> Void
    /// Monotonic turn counter for the history records.
    @ObservationIgnored private var turnIndexCounter = 0
    /// Last time we flushed the transcript mid-stream (throttles disk writes).
    @ObservationIgnored private var lastStreamPersist = Date.distantPast
    /// Produces each turn's event stream (#12 seam). Real = the `claude` CLI; a fake in
    /// tests emits scripted events to exercise the event-handling logic.
    @ObservationIgnored private let turnRunner: ChatTurnRunner

    init(config: Configuration,
         binary: String,
         providerBinaries: [AIProvider: String] = [:],
         providerAPIKeys: [AIProvider: String] = [:],
         codexReasoningEffort: String = "",
         permissionMode: String = "acceptEdits",
         liveSettings: (() -> ChatRunSettings)? = nil,
         turnRunner: ChatTurnRunner = CLIChatTurnRunner(),
         persist: @escaping ([ChatMessage]) -> Void = { _ in },
         onFirstUserMessage: @escaping (String) -> Void = { _ in },
         autoRecommendStrategy: @escaping (String) async -> Strategy? = { _ in nil },
         ensureStrategyFiles: @escaping () -> Void = {},
         persistUsage: @escaping (Int, Double) -> Void = { _, _ in },
         persistActivity: @escaping (TurnActivity) -> Void = { _ in },
         initialHistory: [TurnActivity] = []) {
        self.config = config
        self.liveSettings = liveSettings
        self.turnRunner = turnRunner
        self.snapshotBinary = binary
        self.snapshotProviderBinaries = providerBinaries
        self.snapshotProviderAPIKeys = providerAPIKeys
        self.snapshotCodexEffort = codexReasoningEffort
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
        // NOTE: the run tasks capture self strongly, so this deinit can never fire
        // while a turn is in flight — cancelling a live run from here is unreachable.
        // Teardown MUST go through stop() (AppModel.invalidateChatVM does), which
        // kills the subprocess via the stream's onTermination. The cancels below are
        // only belt-and-braces for the idle case (e.g. a parked narration ticker).
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

    /// Close the review loop (opt-in): hand the independent reviewer's findings back to
    /// the author team as a normal chat turn so it fixes them in place — instead of the
    /// user copying the list by hand. Reviewer ≠ author still holds (the reviewer only
    /// graded; the fix runs through the team's own turn). Sent now if idle, queued behind
    /// a running turn otherwise. Returns false if there was nothing actionable to send.
    @discardableResult
    func requestReviewFixes(_ findings: [ReviewFinding]) -> Bool {
        guard let prompt = DiffReviewer.fixPrompt(findings: findings) else { return false }
        input = prompt
        submit()
        return true
    }

    /// Cap a command's stdout to a readable head+tail (~12KB) so long build/test logs don't
    /// sit in memory verbatim across the whole history of every resident chat.
    static func trimmed(_ s: String, limit: Int = 12_000) -> String {
        guard s.count > limit else { return s }
        let head = s.prefix(limit * 2 / 3)
        let tail = s.suffix(limit / 3)
        let elided = s.count - head.count - tail.count
        return "\(head)\n… [\(elided) chars elided] …\n\(tail)"
    }

    /// Update per-line authorship for `path` after an edit: snapshot the file and diff it
    /// against the previous snapshot, crediting the lines this edit changed to `author`.
    ///
    /// The file read + the (quadratic) line diff run OFF the main actor so a large-file edit
    /// never stutters the UI mid-turn. Correctness is preserved by a per-PATH serial chain:
    /// each edit for a path awaits the previous edit's write before it reads the prior
    /// snapshot, so authorship can't be computed against stale/out-of-order state (different
    /// paths still run concurrently). Best-effort: any read failure just keeps file-level
    /// attribution; if the VM is evicted mid-flight, `weak self` makes it a no-op.
    private func recordLineProvenance(path: String, author: EditProvenance) {
        let previous = provenanceChain[path]
        let task = Task { [weak self] in
            _ = await previous?.value                    // preserve per-path order
            guard let self, !Task.isCancelled else { return }
            // Read the prior snapshot on the main actor, AFTER the previous edit for this
            // path has landed (the await above) — so `old` is never stale/out of order.
            let old = self.fileSnapshots[path] ?? []
            let oldAuthors = self.lineProvenance[path] ?? []
            // Heavy work (read + components + LCS) on a background executor.
            let computed: (authors: [EditProvenance?], lines: [String])? =
                await Task.detached(priority: .utility) {
                    guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
                          size <= 512_000,
                          let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                    let newLines = text.components(separatedBy: "\n")
                    let authors = LineAttributor.attribute(old: old, oldAuthors: oldAuthors,
                                                           new: newLines, author: author)
                    return (authors, newLines)
                }.value
            guard let computed, !Task.isCancelled else { return }
            self.lineProvenance[path] = computed.authors
            self.fileSnapshots[path] = computed.lines
            self.bumpProvenance(path)
        }
        provenanceChain[path] = task
    }

    /// Mark `path` most-recently-used and cap the number of files whose full line-snapshots
    /// stay resident (memory). Evicted files fall back to file-level attribution on their
    /// next edit — the same behaviour as a first-seen file, so no correctness loss.
    private func bumpProvenance(_ path: String) {
        provenanceOrder.removeAll { $0 == path }
        provenanceOrder.append(path)
        while provenanceOrder.count > Self.maxProvenanceFiles {
            let old = provenanceOrder.removeFirst()
            lineProvenance[old] = nil
            fileSnapshots[old] = nil
            provenanceChain[old] = nil
        }
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
        // When isolation is armed, the run happens in the git worktree, not the live tree.
        if let iso = isolation { return iso.path }
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

    // MARK: - Live agent graph (the signature multi-agent moment)

    /// True while a team turn is still ORCHESTRATING — the orchestrator has begun (there's
    /// live narration) but the final prose answer hasn't started streaming yet. This is the
    /// window in which the conversation shows the live agent graph in place of the raw
    /// narration text. (`metaNarration` is `@ObservationIgnored`, but the assistant
    /// message's `text` — which is rendered *from* it — is observable and changes in
    /// lockstep, so the view re-renders at exactly the right moments.)
    var isOrchestrating: Bool {
        isRunning && usesMetaOrchestrator && !metaNarration.isEmpty
    }

    /// A snapshot of the running team mapped onto the `LiveAgentGraphView`'s honest value
    /// model: the configured roster becomes ring nodes (idle until they run), coloured by
    /// role kind so the coral orchestrator core stays the hero; live state comes from
    /// `rolesInProgress` (running), `timeline` role.failed steps (failed), and
    /// `agentsInvolved` (done). Everything here already exists — this is pure projection.
    var liveGraph: LiveGraphSnapshot {
        let strategy = config.strategy
        let failed = Set(timeline.filter { $0.title == "role.failed" }.map(\.detail))
        let nodes: [LiveGraphNode] = strategy.subagentRoles.map { role in
            let name = role.name
            let state: LiveNodeState =
                rolesInProgress.contains(name) ? .running
                : failed.contains(name)        ? .failed
                : agentsInvolved.contains(name) ? .done
                : .idle
            return LiveGraphNode(
                id: name,
                title: name,
                subtitle: roleTasks[name],
                state: state,
                tint: role.role.tint,
                startedAt: roleStartedAt[name])
        }
        let anyRunning = nodes.contains { $0.state == .running }
        let anyFinished = nodes.contains { $0.state == .done || $0.state == .failed }
        let phase: String =
            !isRunning   ? ""
            : anyRunning  ? "working"
            : anyFinished ? "synthesizing"
            : "planning"
        return LiveGraphSnapshot(
            orchestratorTitle: strategy.orchestrator?.name ?? "orchestrator",
            nodes: nodes,
            phase: phase,
            tokens: totalTokens,
            elapsed: turnStartedAt.map { Date().timeIntervalSince($0) } ?? 0,
            running: isRunning)
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
            errorText = L10n.string("chat.error.missingFolder", langCode: narrationLang)
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
        var promptText = promptBody + effort.promptDirective
        if grillMe { promptText += Self.grillDirective }   // interrogate me before implementing
        if proposeApproaches { promptText += Self.approachesDirective }   // N approaches, I pick
        // On the FIRST turn of a session, inject the repo's code map (when graphify has
        // built one) so the agent opens with structure instead of spending its window
        // re-reading files to rebuild the same map. It persists via session resume, so
        // later turns don't re-send it. No graph for this repo → nothing injected, no cost.
        if messages.isEmpty, let inj = CodeMapContext.shared.injection(forRepo: repo) {
            promptText = inj.preamble + "\n\n---\n\n" + promptText
            CodeMapContext.shared.record(inj, repoName: URL(fileURLWithPath: repo).lastPathComponent)
        }
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
        roleLiveLine = [:]
        rolesRunning = [:]
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
            do {
                _ = try StrategyWriter(repoURL: URL(fileURLWithPath: repo), binary: binary)
                    .write(strategy: config.strategy)
            } catch {
                // Scratch-folder write failed → the run would use no/stale team files.
                DiagnosticsLog.record("Couldn't write scratch team files: \(error.localizedDescription)")
            }
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
        runEpoch += 1
        let epoch = runEpoch
        runTask = Task { [binary, model, useMeta, epoch] in
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
            // A newer run superseded this one (stop→send): it now owns isRunning, the
            // message list and the queue — this stale epilogue must not touch any of them.
            guard epoch == runEpoch else { return }
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
    /// Internal (not private) so tests can drive it directly through a fake ChatTurnRunner
    /// (the #12 seam) — the whole point of the seam is to exercise this event handling
    /// without spawning `claude`.
    func runTurn(text: String, repo: String, sessionID: String, resume: Bool,
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
            stream = turnRunner.streamAsking(binary: binary, repoPath: repo, prompt: text,
                                             model: model, sessionID: sessionID, resume: resume,
                                             extraDirs: extraDirs, responder: responder)
        } else {
            stream = turnRunner.stream(binary: binary, repoPath: repo, prompt: text, model: model,
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
                appendStep(ActivityStep(title: name, detail: detail, at: Date(),
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
                    // PERF/memory: a build/test can emit hundreds of KB; kept verbatim ×50
                    // turns ×every resident chat that adds up fast. Keep head+tail (~12KB),
                    // enough to read the gist, and elide the middle.
                    commandLog.append(CommandRun(command: cmd, output: Self.trimmed(output), at: Date()))
                    pendingCommands[id] = nil
                }
            case .todos(let items):
                todos = items
            case .fileEdited(let path):
                if !editedFiles.contains(path) { editedFiles.append(path) }
                if !turnEditedFiles.contains(path) { turnEditedFiles.append(path) }
                // Credit the change to whoever was active — the delegated subagent (with
                // its pinned model) or the orchestrator. Last editor wins for the file dot;
                // the per-line map credits exactly the lines this edit changed.
                let author = EditProvenanceResolver.attribute(subagent: activeSubagent,
                                                              strategy: config.strategy)
                fileProvenance[path] = author
                recordLineProvenance(path: path, author: author)
            case .skillUsed(let slug):
                if !turnSkillsUsed.contains(slug) { turnSkillsUsed.append(slug) }
                if !skillsUsed.contains(slug) { skillsUsed.append(slug) }
                activity.append("skill: \(slug)")
                appendStep(ActivityStep(title: "Skill", detail: slug, at: Date(),
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
        // Isolate the ticker to the main actor: its body calls renderNarration(), which
        // reads metaNarration and writes messages[assistantIndex].text — the same state
        // apply() mutates from the event loop. An unisolated Task would run that off the
        // main executor and race the event handling; @MainActor serializes both paths.
        narrationTicker = Task { @MainActor [weak self] in
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

    /// Append a timeline step, collapsing an *immediate* duplicate (same title, detail,
    /// agent and delegation flag) into the one already there. A streaming CLI sometimes
    /// re-emits the identical tool marker back-to-back; without this the timeline shows
    /// the same row several times, which reads as the run being stuck.
    private func appendStep(_ step: ActivityStep) {
        if let last = timeline.last,
           last.title == step.title, last.detail == step.detail,
           last.agent == step.agent, last.isDelegation == step.isDelegation {
            return
        }
        timeline.append(step)
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
        case .rolePlanned(let counts):
            // Authoritative instances-per-role from the plan, emitted before any worker
            // starts. Pre-populate the running count so finish/fail events decrement a
            // correct total and a role stays "working" until its LAST instance completes,
            // regardless of the order events arrive from the concurrent workers.
            for (role, n) in counts where n > 0 { rolesRunning[role] = n }
        case .roleStarted(let role, _, let model, let task):
            if role == orchName {
                activeSubagent = nil
            } else {
                let brief = task.trimmingCharacters(in: .whitespacesAndNewlines)
                // The meta path can re-emit the SAME roleStarted marker several times for
                // one worker (heartbeats / repeated delegation lines). Only record the
                // delegation + "working" steps and narrate on the FIRST start of a given
                // role+task — otherwise the timeline fills with identical rows all stamped
                // at the same second, which reads as "stuck / repeating 3× / 9×".
                let alreadyRunning = rolesInProgress.contains(role)
                    && !brief.isEmpty && roleTasks[role] == brief
                activeSubagent = role
                rolesInProgress.insert(role)
                // Instance accounting is authoritative from `.rolePlanned` (emitted before
                // any worker starts), NOT incremented here — worker start/finish events
                // arrive out of order across threads, so counting on start would race.
                // Model + task are set ONCE per role: all instances of a role share the
                // same model, and a later instance's roleStarted (or a heartbeat re-emit)
                // must not overwrite the first-recorded task with a different/stale value.
                if roleModels[role] == nil { roleModels[role] = model }
                if roleTasks[role] == nil, !brief.isEmpty { roleTasks[role] = brief }
                if !agentsInvolved.contains(role) { agentsInvolved.append(role) }
                if !alreadyRunning {
                    activity.append("→ \(role)")
                    // Earliest instance's start drives the live timer (don't let a later
                    // instance reset it), so the elapsed reflects the whole fan-out.
                    if roleStartedAt[role] == nil { roleStartedAt[role] = Date() }
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
            }
        case .roleActivity(let role, let title, let detail):
            // A live tool step streamed from a worker/orchestrator mid-call — attribute it
            // to the agent (orchestrator steps carry agent: nil, like the Claude path) so
            // the timeline and each agent's drill-down fill in real time. appendStep dedups
            // an immediate repeat.
            let isOrch = (role == orchName)
            if isOrch { activeSubagent = nil }
            appendStep(ActivityStep(title: title, detail: detail, at: Date(),
                                    isDelegation: false, agent: isOrch ? nil : role))
        case .authRequired(let provider):
            // A provider's login is stale — surface a one-tap Reconnect (the run fails fast
            // rather than hanging on a prompt no one can answer).
            needsReauth = provider
        case .roleNarration(let role, let text):
            // Rolling "what it's doing now" for a provider with no structured tool stream.
            let key = (role == orchName) ? (orchName ?? role) : role
            roleLiveLine[key] = text
        case .roleFile(let role, let path):
            if !editedFiles.contains(path) { editedFiles.append(path) }
            if !turnEditedFiles.contains(path) { turnEditedFiles.append(path) }
            let author = EditProvenanceResolver.attribute(subagent: (role == orchName) ? nil : role,
                                                          strategy: config.strategy)
            fileProvenance[path] = author
            recordLineProvenance(path: path, author: author)
        case .roleFinished(let role, let tokens):
            // Exact per-agent + per-model attribution on the cross-provider path.
            if tokens > 0 {
                tokensByAgent[role, default: 0] += tokens
                if let m = roleModels[role] { tokensByModel[m, default: 0] += tokens }
            }
            if role != orchName {
                // One instance finished — mark the ROLE done only when the LAST running
                // instance completes, so a researcher ×3 stays "working" until all three do.
                let remaining = max(0, (rolesRunning[role] ?? 1) - 1)
                rolesRunning[role] = remaining
                // Attribute a completed step to THIS instance so the timeline reflects it.
                timeline.append(ActivityStep(title: "role.done", detail: role, at: Date(),
                                             isDelegation: false, agent: role))
                if remaining == 0 {
                    rolesInProgress.remove(role)
                    roleStartedAt[role] = nil
                    roleLiveLine[role] = nil
                    markNarrationDone(role, assistantIndex: assistantIndex)
                }
            }
        case .roleFailed(let role, let message):
            // One worker failed but the run continues with the others — record it and
            // mark this agent's narration line as failed so the UI isn't left "working".
            let remaining = max(0, (rolesRunning[role] ?? 1) - 1)
            rolesRunning[role] = remaining
            if remaining == 0 {
                rolesInProgress.remove(role)
                roleStartedAt[role] = nil
                roleLiveLine[role] = nil
            }
            DiagnosticsLog.record("meta worker “\(role)” failed — \(message)")
            if let i = metaNarration.lastIndex(where: { $0.contains(role) && $0.hasPrefix("▸") }) {
                metaNarration[i] = "⚠ \(role)"
                narrationStepSince = Date()
                renderNarration(assistantIndex)
            }
            // Record ONE failed step per role — a fanned-out role (researcher ×8) whose provider
            // login expired fails every instance, but the timeline should show a single "⚠"
            // line, not eight identical ones stacked at the same second.
            if !timeline.contains(where: { $0.title == "role.failed" && $0.detail == role }) {
                timeline.append(ActivityStep(title: "role.failed", detail: role, at: Date(),
                                             isDelegation: false, agent: role))
            }
        case .assistantText(let text):
            // The final synthesis replaces the live narration. The answer stays in the
            // transcript only — it is NOT written to disk as a file (a plain response is
            // not a "download"; only real files the agents write with tools are listed).
            metaNarration = []
            narrationStepSince = nil
            if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = text }
            persistStreaming()
        case .usage(let tokens, let cost, let estimated):
            totalTokens += tokens
            totalCostUSD += cost
            if estimated { costEstimated = true }
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
        deniedTools = []; errorText = nil; needsReauth = nil; activity = []; activeSubagent = nil
        agentsInvolved = []; timeline = []; todos = []; turnStartedAt = Date()
        roleLiveLine = [:]; rolesRunning = [:]
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
        runEpoch += 1
        let epoch = runEpoch
        runTask = Task { [binary, model, useMeta, epoch] in
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
            guard epoch == runEpoch else { return }   // a newer run owns the state now
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
