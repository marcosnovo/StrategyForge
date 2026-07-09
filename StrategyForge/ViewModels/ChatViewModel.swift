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
    let config: Configuration
    private let binary: String

    var messages: [ChatMessage] = []
    /// Tools the agent used during the current turn (shown as a status line).
    var activity: [String] = []
    /// Absolute paths of files the agent has written/edited in this chat.
    var editedFiles: [String] = []
    /// The subagent the orchestrator is currently delegating to (if any).
    var activeSubagent: String?
    /// Tool uses the last run wasn't permitted to perform (→ offer allow & retry).
    var deniedTools: [String] = []
    /// Files staged to attach to the next message for Claude to review.
    var attachments: [Attachment] = []
    /// Dirs granted for the last run (reused on allow-and-retry).
    @ObservationIgnored private var lastExtraDirs: [String] = []
    var input = ""
    var isRunning = false
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
    /// Writes the strategy's .claude files into the repo so the run actually uses
    /// the configured team. Called right before each run (idempotent).
    @ObservationIgnored private let ensureStrategyFiles: () -> Void
    private let permissionMode: String
    /// Persists cumulative usage (tokens, cost).
    @ObservationIgnored private let persistUsage: (Int, Double) -> Void

    init(config: Configuration,
         binary: String,
         permissionMode: String = "acceptEdits",
         persist: @escaping ([ChatMessage]) -> Void = { _ in },
         onFirstUserMessage: @escaping (String) -> Void = { _ in },
         ensureStrategyFiles: @escaping () -> Void = {},
         persistUsage: @escaping (Int, Double) -> Void = { _, _ in }) {
        self.config = config
        self.binary = binary
        self.permissionMode = permissionMode
        self.persist = persist
        self.onFirstUserMessage = onFirstUserMessage
        self.ensureStrategyFiles = ensureStrategyFiles
        self.persistUsage = persistUsage
        self.messages = config.transcript
        self.input = config.draft   // restore unsent text
        self.totalTokens = config.totalTokens
        self.totalCostUSD = config.totalCostUSD
        // A prior transcript implies the repo already has a Claude Code session.
        self.hasSession = !config.transcript.isEmpty
    }

    /// Orchestrator (session) model — the launch model, per Claude Code's rules.
    var model: String { config.strategy.orchestrator?.model.rawValue ?? "claude-fable-5" }
    var canSend: Bool {
        let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachments.isEmpty) && !isRunning
    }

    /// The folder Claude runs in: the chosen repo, or a per-chat scratch folder so
    /// questions / document reviews work without picking a project.
    private func workingDirectory() -> String {
        if let repo = config.repoPath, !repo.isEmpty { return repo }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("StrategyForge/sessions/\(config.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    func send() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning else { return }
        // Allow sending attachments alone with a sensible default ask.
        if text.isEmpty, !attachments.isEmpty { text = "Please review the attached files." }
        guard !text.isEmpty else { return }
        let repo = workingDirectory()

        // Fold any attached files into the prompt + grant read access to their dirs.
        let atts = attachments
        attachments = []
        let extraDirs = Array(Set(atts.map { $0.url.deletingLastPathComponent().path }))
        lastExtraDirs = extraDirs
        let promptText: String = atts.isEmpty ? text
            : text + "\n\nAttached files to review:\n" + atts.map { "- \($0.name): \($0.url.path)" }.joined(separator: "\n")
        let displayText: String = atts.isEmpty ? text
            : text + "\n\n📎 " + atts.map { $0.name }.joined(separator: ", ")

        input = ""
        errorText = nil
        activity = []
        activeSubagent = nil
        deniedTools = []
        if messages.isEmpty { onFirstUserMessage(text) }   // auto-title the chat
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
        runTask = Task { [binary, model, permissionMode] in
            // Try to resume; if the CLI has no session with this id (e.g. a chat from
            // before per-chat sessions existed), start fresh once, invisibly.
            var missing = await runTurn(text: promptText, repo: repo, sessionID: sessionID,
                                        resume: resume, assistantIndex: assistantIndex,
                                        binary: binary, model: model, permissionMode: permissionMode,
                                        extraDirs: extraDirs)
            if missing, resume {
                if messages.indices.contains(assistantIndex) { messages[assistantIndex].text = "" }
                activity = []; activeSubagent = nil
                missing = await runTurn(text: promptText, repo: repo, sessionID: sessionID,
                                        resume: false, assistantIndex: assistantIndex,
                                        binary: binary, model: model, permissionMode: permissionMode,
                                        extraDirs: extraDirs)
            }
            isRunning = false
            hasSession = true
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
            case .assistantText(let chunk):
                guard !gotDelta else { break }
                if !messages[assistantIndex].text.isEmpty {
                    messages[assistantIndex].text += "\n\n"
                }
                messages[assistantIndex].text += chunk
            case .tool(let name):
                activity.append(name)
                separatorPending = true
            case .delegated(let subagent):
                activeSubagent = subagent
                activity.append("→ \(subagent)")
                separatorPending = true
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

    /// Re-run the last user message granting full permissions — the "allow & retry"
    /// path when a run was blocked by permission denials.
    func retryAllowingAll() {
        guard !isRunning, let repo = config.repoPath,
              let lastUser = messages.last(where: { $0.role == .user })?.text else { return }
        deniedTools = []; errorText = nil; activity = []; activeSubagent = nil
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isRunning = true
        let sessionID = config.id.uuidString.lowercased()
        runTask = Task { [binary, model] in
            _ = await runTurn(text: lastUser, repo: repo, sessionID: sessionID, resume: true,
                              assistantIndex: assistantIndex, binary: binary, model: model,
                              permissionMode: "bypassPermissions", extraDirs: lastExtraDirs)
            isRunning = false
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
    }
}
