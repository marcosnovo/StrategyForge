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
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning && config.repoPath != nil
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning, let repo = config.repoPath else { return }

        input = ""
        errorText = nil
        activity = []
        activeSubagent = nil
        if messages.isEmpty { onFirstUserMessage(text) }   // auto-title the chat
        ensureStrategyFiles()   // make sure .claude/agents + CLAUDE.md are in the repo
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isRunning = true
        let resume = hasSession
        persist(messages) // save the question immediately, before the (long) run

        let sessionID = config.id.uuidString.lowercased()
        var gotDelta = false          // did live streaming deliver text this turn?
        var separatorPending = false  // insert a blank line before the next text
        runTask = Task { [binary, model, permissionMode] in
            for await event in ClaudeRunner.stream(binary: binary, repoPath: repo,
                                                   prompt: text, model: model,
                                                   sessionID: sessionID, resume: resume,
                                                   permissionMode: permissionMode) {
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
                    // Only used as a fallback when partial streaming didn't deliver.
                    guard !gotDelta else { break }
                    if !messages[assistantIndex].text.isEmpty {
                        messages[assistantIndex].text += "\n\n"
                    }
                    messages[assistantIndex].text += chunk
                case .tool(let name):
                    activity.append(name)
                    separatorPending = true   // start a new paragraph after a tool step
                case .delegated(let subagent):
                    activeSubagent = subagent
                    activity.append("→ \(subagent)")
                    separatorPending = true
                case .fileEdited(let path):
                    if !editedFiles.contains(path) { editedFiles.append(path) }
                case .usage(let tokens, let cost):
                    totalTokens += tokens
                    totalCostUSD += cost
                    persistUsage(totalTokens, totalCostUSD)
                case .finished:
                    break
                case .failed(let message):
                    errorText = message
                }
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

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }
}
