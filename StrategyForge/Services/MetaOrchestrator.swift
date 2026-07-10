//
//  MetaOrchestrator.swift
//  StrategyForge
//
//  Level 2 engine: StrategyForge's OWN cross-provider orchestrator. It drives the
//  Plan → Delegate → Synthesize loop across a team whose roles may run on different
//  providers (a GPT orchestrator delegating to Gemini workers and a Claude advisor,
//  etc.) — something no single vendor CLI can do, since each only delegates to its
//  own models. Each step is one `OneShotRunner` call; the runner is injected so the
//  loop is unit-tested with a mock and run for real with the CLI-backed runner.
//
//  Pure helpers (prompt building, plan parsing, model resolution) are static and
//  tested directly; `run` wires them to the runner and emits progress events.
//

import Foundation

/// Progress emitted by a meta-orchestration run, for the activity UI.
enum MetaEvent: Sendable, Equatable {
    case phase(String)                                   // "plan" | "delegate" | "synthesize"
    case roleStarted(role: String, provider: AIProvider, model: String)
    case roleFinished(role: String, tokens: Int)
    case assistantText(String)                           // the final synthesized answer
    case usage(tokens: Int, costUSD: Double)             // totals across every call
    case failed(String)
    case finished
}

struct MetaOrchestrator {

    /// One delegated unit of work: which agent (by role name) does what.
    struct Subtask: Equatable, Sendable {
        let roleName: String
        let task: String
    }

    // MARK: - Model resolution

    /// The model id to pass to the CLI for a role, honoring its provider.
    static func modelID(for role: AgentRole) -> String {
        if role.provider == .claude { return role.model.rawValue }
        return role.providerModelID ?? role.provider.models.first?.id ?? ""
    }

    // MARK: - Prompt building (pure)

    static func planPrompt(task: String, workers: [AgentRole]) -> String {
        let roster = workers.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        return """
        You are the orchestrator of a team of AI agents. Break the user's task into \
        independent subtasks that can run in parallel — at most one per agent, only \
        where an agent genuinely helps.

        USER TASK:
        \(task)

        AVAILABLE AGENTS:
        \(roster)

        Respond with ONLY a JSON array, no prose, no code fences:
        [{"role":"<agent name>","task":"<what that agent should do>"}]
        """
    }

    /// The prompt handed to a worker: its own system prompt (the role's persona /
    /// instructions), parallel-instance context, then the delegated subtask.
    static func workerPrompt(role: AgentRole, task: String, instance: Int, of total: Int) -> String {
        var p = ""
        let sp = role.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if sp.isEmpty {
            p += "You are \(role.name), a \(role.role.displayName.lowercased()) on a team.\n\n"
        } else {
            p += sp + "\n\n"
        }
        if total > 1 {
            p += "You are instance \(instance + 1) of \(total) working on this in parallel — focus on your share and be concise.\n\n"
        }
        p += "Task:\n\(task)"
        return p
    }

    static func synthesisPrompt(task: String, results: [(role: String, text: String)]) -> String {
        let blocks = results.map { "### \($0.role)\n\($0.text)" }.joined(separator: "\n\n")
        return """
        You are the orchestrator. Combine your agents' results into a single, coherent \
        final answer for the user. Resolve conflicts, remove redundancy, and keep it \
        actionable.

        USER TASK:
        \(task)

        AGENT RESULTS:
        \(blocks)

        Write the final answer only.
        """
    }

    // MARK: - Plan parsing (pure, tolerant)

    /// Parse the orchestrator's plan into subtasks. Tolerant: extracts the first
    /// JSON array even if wrapped in prose/fences, maps loose role names to real
    /// worker names, and falls back to "one subtask per worker" when parsing fails.
    static func parsePlan(_ text: String, workers: [AgentRole], task: String) -> [Subtask] {
        func fallback() -> [Subtask] { workers.map { Subtask(roleName: $0.name, task: task) } }
        guard !workers.isEmpty else { return [] }

        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return fallback()
        }

        var subtasks: [Subtask] = []
        for item in arr {
            guard let roleRaw = item["role"] as? String,
                  let t = item["task"] as? String, !t.isEmpty else { continue }
            // Map the model's role name onto a real worker (loose match).
            let match = workers.first { StrategyDiagramView.titlesMatch($0.name, roleRaw) }
                ?? workers.first { $0.name.caseInsensitiveCompare(roleRaw) == .orderedSame }
            if let role = match {
                subtasks.append(Subtask(roleName: role.name, task: t))
            }
        }
        return subtasks.isEmpty ? fallback() : subtasks
    }

    // MARK: - Run

    /// Execute the loop. Returns the final synthesized text (nil on failure). Emits
    /// progress via `onEvent`. `runner` performs each single model call.
    @discardableResult
    static func run(strategy: Strategy,
                    task: String,
                    cwd: String?,
                    runner: OneShotRunner,
                    onEvent: @escaping @Sendable (MetaEvent) -> Void) async -> String? {
        guard let orchestrator = strategy.orchestrator else {
            onEvent(.failed("This team has no orchestrator.")); return nil
        }
        let orchModel = modelID(for: orchestrator)
        let workers = strategy.subagentRoles
        var totalTokens = 0
        var totalCost = 0.0

        func account(_ r: OneShotResult) { totalTokens += r.tokens; totalCost += r.costUSD }

        do {
            if Task.isCancelled { return nil }
            // Solo team: no workers → the orchestrator just answers directly.
            if workers.isEmpty {
                onEvent(.phase("plan"))
                onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
                let r = try await runner.run(prompt: task, provider: orchestrator.provider, model: orchModel, cwd: cwd)
                account(r)
                onEvent(.roleFinished(role: orchestrator.name, tokens: r.tokens))
                onEvent(.assistantText(r.text))
                onEvent(.usage(tokens: totalTokens, costUSD: totalCost))
                onEvent(.finished)
                return r.text
            }

            // 1) PLAN.
            onEvent(.phase("plan"))
            onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
            let planRes = try await runner.run(prompt: planPrompt(task: task, workers: workers),
                                               provider: orchestrator.provider, model: orchModel, cwd: cwd)
            account(planRes)
            onEvent(.roleFinished(role: orchestrator.name, tokens: planRes.tokens))
            let subtasks = parsePlan(planRes.text, workers: workers, task: task)

            // 2) DELEGATE — run subtasks CONCURRENTLY (cheap parallel labor), honoring
            // each role's system prompt and instance count. Results are collected and
            // accounted on the parent context to avoid data races.
            onEvent(.phase("delegate"))
            if Task.isCancelled { return nil }
            struct WorkerResult: Sendable { let order: Int; let role: String; let text: String; let tokens: Int; let cost: Double }
            let collected = try await withThrowingTaskGroup(of: WorkerResult.self) { group -> [WorkerResult] in
                var order = 0
                for sub in subtasks {
                    guard let role = workers.first(where: { $0.name == sub.roleName }) else { continue }
                    let m = modelID(for: role)
                    let instances = max(1, min(role.count, 8))
                    for inst in 0..<instances {
                        let thisOrder = order; order += 1
                        let prompt = workerPrompt(role: role, task: sub.task, instance: inst, of: instances)
                        group.addTask {
                            onEvent(.roleStarted(role: role.name, provider: role.provider, model: m))
                            let r = try await runner.run(prompt: prompt, provider: role.provider, model: m, cwd: cwd)
                            onEvent(.roleFinished(role: role.name, tokens: r.tokens))
                            return WorkerResult(order: thisOrder, role: role.name, text: r.text, tokens: r.tokens, cost: r.costUSD)
                        }
                    }
                }
                var out: [WorkerResult] = []
                for try await r in group { out.append(r) }
                return out.sorted { $0.order < $1.order }
            }
            for r in collected { totalTokens += r.tokens; totalCost += r.cost }
            let results: [(role: String, text: String)] = collected.map { ($0.role, $0.text) }

            if Task.isCancelled { return nil }
            // 3) SYNTHESIZE — the orchestrator combines everything.
            onEvent(.phase("synthesize"))
            onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
            let synth = try await runner.run(prompt: synthesisPrompt(task: task, results: results),
                                             provider: orchestrator.provider, model: orchModel, cwd: cwd)
            account(synth)
            onEvent(.roleFinished(role: orchestrator.name, tokens: synth.tokens))

            onEvent(.assistantText(synth.text))
            onEvent(.usage(tokens: totalTokens, costUSD: totalCost))
            onEvent(.finished)
            return synth.text
        } catch {
            // A cancelled turn shouldn't surface as an error.
            if Task.isCancelled || error is CancellationError { return nil }
            let msg = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
            onEvent(.failed(msg))
            return nil
        }
    }
}
