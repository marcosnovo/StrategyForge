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
    case rolePlanned(counts: [String: Int])              // authoritative instances-per-role from the plan
    case roleStarted(role: String, provider: AIProvider, model: String, task: String = "")
    case roleActivity(role: String, title: String, detail: String?)  // a live tool step by a role
    case roleNarration(role: String, text: String)       // rolling "what it's doing now" (Codex/Gemini)
    case roleFile(role: String, path: String)            // a file a role wrote/edited (live)
    case roleFinished(role: String, tokens: Int)
    case roleFailed(role: String, message: String)       // one worker failed; others go on
    case authRequired(AIProvider)                        // a provider needs re-login (fail fast, offer Reconnect)
    case assistantText(String)                           // the final synthesized answer
    case usage(tokens: Int, costUSD: Double, estimated: Bool = false)  // totals across every call
    case failed(String)
    case finished
}

struct MetaOrchestrator {

    /// One delegated unit of work: which agent (by role name) does what.
    struct Subtask: Equatable, Sendable {
        let roleName: String
        let task: String
    }

    /// Tracks which providers have reported an expired login during a delegation fan-out, so
    /// the Reconnect prompt is raised once per provider and doomed siblings skip their launch.
    actor AuthGate {
        private var tripped: Set<AIProvider> = []
        /// Records `p` as auth-failed; returns true only the FIRST time (so the caller emits
        /// the reconnect prompt exactly once per provider).
        func trip(_ p: AIProvider) -> Bool { tripped.insert(p).inserted }
        func isTripped(_ p: AIProvider) -> Bool { tripped.contains(p) }
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
        p += "Task:\n\(task)\n\n"
        // Pass EVIDENCE, not just a conclusion (Hanako 2026): the next agent inherits this and
        // cannot reason from a bare line. Report what you RULED OUT and what FAILED, not only
        // what worked — the dead ends are the part that stops a teammate re-walking them.
        p += "When you report back, include a short \"Ruled out / failed:\" section listing the "
           + "approaches, endpoints or assumptions you tried that did NOT work (and why), plus any "
           + "concrete artifact (a schema, an exact error, a file path) — so a teammate never has "
           + "to rediscover it. Don't just give the final conclusion."
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

        guard let arr = ModelJSON.firstArray(in: text) else { return fallback() }

        var subtasks: [Subtask] = []
        for item in arr {
            guard let roleRaw = item["role"] as? String,
                  let t = item["task"] as? String, !t.isEmpty else { continue }
            // Map the model's role name onto a real worker (loose match).
            let match = workers.first { AgentNameMatcher.titlesMatch($0.name, roleRaw) }
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
    /// Run one leg, re-labelling any failure with the role, provider and model so a
    /// cross-provider failure says exactly which agent broke and why (the raw CLI
    /// stderr is otherwise anonymous — the #1 confusion with mixed-provider runs).
    private static func runStep(_ runner: OneShotRunner, role: String, provider: AIProvider,
                                model: String, prompt: String, cwd: String?,
                                onActivity: (@Sendable (OneShotEvent) -> Void)? = nil) async throws -> OneShotResult {
        do {
            if let onActivity {
                return try await runner.run(prompt: prompt, provider: provider, model: model, cwd: cwd, onEvent: onActivity)
            }
            return try await runner.run(prompt: prompt, provider: provider, model: model, cwd: cwd)
        } catch let e as OneShotError {
            if case .notInstalled = e { throw e }   // already actionable
            if case .authRequired = e { throw e }   // keep typed → UI offers Reconnect
            let modelLabel = model.isEmpty ? "default model" : model
            throw OneShotError.failed("“\(role)” (\(provider.displayName) · \(modelLabel)) failed — \(e.errorDescription ?? "unknown error")")
        }
    }

    @discardableResult
    static func run(strategy: Strategy,
                    task: String,
                    cwd: String?,
                    runner: OneShotRunner,
                    authCheck: @escaping @Sendable (AIProvider) -> ProviderAuth.State = { ProviderAuth.freshness($0) },
                    onEvent: @escaping @Sendable (MetaEvent) -> Void) async -> String? {
        guard let orchestrator = strategy.orchestrator else {
            onEvent(.failed("This team has no orchestrator.")); return nil
        }
        let orchModel = modelID(for: orchestrator)
        let workers = strategy.subagentRoles

        // PRE-FLIGHT auth. A provider whose stored login is MISSING or EXPIRED makes its CLI
        // HANG (Gemini especially) instead of failing fast — so launching its workers would
        // burn the FULL 10-minute watchdog per instance. That's the "se tiró 10 minutos y
        // falló, gastando tokens a lo tonto" bug. Detect stale logins up front (cheap, on-disk,
        // no subprocess, no Keychain), surface Reconnect immediately, and treat those providers
        // as unavailable: their workers are skipped (never launched), and if the ORCHESTRATOR
        // itself can't authenticate we fail in seconds, not minutes.
        let staleProviders: Set<AIProvider> = Set(([orchestrator] + workers).map(\.provider))
            .filter { let s = authCheck($0); return s == .missing || s == .expired }
        for p in staleProviders { onEvent(.authRequired(p)) }
        if staleProviders.contains(orchestrator.provider) {
            onEvent(.failed("\(orchestrator.provider.displayName) needs you to sign in again — reconnect it in Providers, then retry."))
            return nil
        }

        // Map a role's live one-shot events onto MetaEvents, so the timeline fills with
        // each agent's tool steps AS they happen (Claude workers/orchestrator stream via
        // stream-json; other providers stay buffered).
        func activity(_ roleName: String) -> @Sendable (OneShotEvent) -> Void {
            { ev in
                switch ev {
                case .tool(let name, let detail):
                    onEvent(.roleActivity(role: roleName, title: name, detail: detail))
                case .fileEdited(let path):
                    onEvent(.roleFile(role: roleName, path: path))
                case .progress(let text):
                    onEvent(.roleNarration(role: roleName, text: text))
                }
            }
        }

        do {
            if Task.isCancelled { return nil }
            // Solo team: no workers → the orchestrator just answers directly.
            if workers.isEmpty {
                onEvent(.phase("plan"))
                onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
                let r = try await runStep(runner, role: orchestrator.name, provider: orchestrator.provider, model: orchModel, prompt: task, cwd: cwd,
                                          onActivity: activity(orchestrator.name))
                onEvent(.roleFinished(role: orchestrator.name, tokens: r.tokens))
                // Usage is emitted as a DELTA per step so the live counter climbs during
                // the run (not just at the end); ChatViewModel accumulates the deltas.
                onEvent(.usage(tokens: r.tokens, costUSD: r.costUSD, estimated: r.estimated))
                onEvent(.assistantText(r.text))
                onEvent(.finished)
                return r.text
            }

            // 1) PLAN.
            onEvent(.phase("plan"))
            onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
            let planRes = try await runStep(runner, role: orchestrator.name, provider: orchestrator.provider,
                                            model: orchModel, prompt: planPrompt(task: task, workers: workers), cwd: cwd,
                                            onActivity: activity(orchestrator.name))
            onEvent(.roleFinished(role: orchestrator.name, tokens: planRes.tokens))
            onEvent(.usage(tokens: planRes.tokens, costUSD: planRes.costUSD, estimated: planRes.estimated))
            let subtasks = parsePlan(planRes.text, workers: workers, task: task)

            // 2) DELEGATE — run subtasks CONCURRENTLY (cheap parallel labor), honoring
            // each role's system prompt and instance count. Results are collected and
            // accounted on the parent context to avoid data races.
            onEvent(.phase("delegate"))
            if Task.isCancelled { return nil }
            // How many DISTINCT subtasks the plan gave each role. When the planner already
            // split a role into several subtasks, those subtasks ARE the parallelism — run
            // ONE instance each. Only fan a role that got a SINGLE subtask out to role.count.
            // (Without this, K subtasks × count instances multiplied — e.g. 4×3 = 12 Gemini
            // calls for one query, the "×12 researcher" bug.)
            let subtasksPerRole = Dictionary(grouping: subtasks, by: { $0.roleName }).mapValues(\.count)
            DiagnosticsLog.record("meta plan: \(subtasks.count) subtask(s) → " +
                subtasksPerRole.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: ", "))
            let globalInstanceCap = 8   // hard ceiling on total parallel workers per turn
            // Pre-compute how many instances each role will ACTUALLY run — same order +
            // fan-out + cap logic as the delegation loop below — and tell the UI up front.
            // The concurrent task group emits roleStarted/roleFinished from many threads
            // with no ordering guarantee, so a roleFinished can land before its matching
            // roleStarted; without an authoritative up-front count the UI would decrement
            // a role to "done" too early (the "seems like only one agent ran" symptom).
            var plannedInstances: [String: Int] = [:]
            do {
                var order = 0
                for sub in subtasks {
                    guard let role = workers.first(where: { $0.name == sub.roleName }) else { continue }
                    let hasSiblings = (subtasksPerRole[sub.roleName] ?? 1) > 1
                    let instances = hasSiblings ? 1 : max(1, min(role.count, globalInstanceCap))
                    for _ in 0..<instances {
                        if order >= globalInstanceCap { break }
                        order += 1
                        plannedInstances[role.name, default: 0] += 1
                    }
                }
            }
            onEvent(.rolePlanned(counts: plannedInstances))
            struct WorkerResult: Sendable { let order: Int; let role: String; let text: String; let tokens: Int; let cost: Double }
            // Fault-tolerant: one worker failing must NOT cancel its siblings or hang the
            // turn. (A THROWING task group cancels every sibling on the first error and
            // then awaits them — a stuck/slow subprocess would block the whole run.) Each
            // worker catches its own error; we synthesize from whatever succeeded and only
            // fail the turn if EVERY worker failed.
            // When a provider's login is expired, EVERY instance of it will fail the same way.
            // Without this gate a "researcher ×8" on an expired Gemini login launched 8 doomed
            // subprocesses and emitted 8 identical failures (the "8× ⚠ researcher" the founder
            // saw). The gate lets the FIRST auth failure surface the Reconnect prompt once, and
            // its still-pending siblings skip their subprocess — they just decrement the count.
            let authGate = AuthGate()
            // Pre-trip the gate for providers we already know are signed out, so their workers
            // skip the (doomed, hang-prone) subprocess launch entirely.
            for p in staleProviders { _ = await authGate.trip(p) }
            let collected = await withTaskGroup(of: WorkerResult?.self) { group -> [WorkerResult] in
                var order = 0
                for sub in subtasks {
                    guard let role = workers.first(where: { $0.name == sub.roleName }) else { continue }
                    let m = modelID(for: role)
                    let hasSiblings = (subtasksPerRole[sub.roleName] ?? 1) > 1
                    let instances = hasSiblings ? 1 : max(1, min(role.count, globalInstanceCap))
                    for inst in 0..<instances {
                        if order >= globalInstanceCap {
                            DiagnosticsLog.record("meta delegate: hit \(globalInstanceCap)-worker cap, dropping extra instances")
                            break
                        }
                        let thisOrder = order; order += 1
                        let providerName = role.provider.displayName   // capture off-actor for the @Sendable task
                        let prompt = workerPrompt(role: role, task: sub.task, instance: inst, of: instances)
                        let taskPreview = sub.task.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines)
                        DiagnosticsLog.record("meta start #\(thisOrder + 1): \(role.name) inst \(inst + 1)/\(instances) · \(role.provider.displayName)·\(m.isEmpty ? "default" : m) · task=\(taskPreview)")
                        group.addTask {
                            // A sibling of this provider already reported an expired login —
                            // don't launch another doomed subprocess. Still emit roleFailed so
                            // the UI's instance count decrements (the role won't hang "working").
                            if await authGate.isTripped(role.provider) {
                                onEvent(.roleFailed(role: role.name,
                                                    message: "\(providerName) needs you to sign in again — reconnect and retry."))
                                return nil
                            }
                            onEvent(.roleStarted(role: role.name, provider: role.provider, model: m, task: sub.task))
                            do {
                                let r = try await runStep(runner, role: role.name, provider: role.provider, model: m, prompt: prompt, cwd: cwd,
                                                      onActivity: activity(role.name))
                                DiagnosticsLog.record("meta done #\(thisOrder + 1): \(role.name) · \(r.tokens) tok" + (r.estimated ? " (est)" : ""))
                                onEvent(.roleFinished(role: role.name, tokens: r.tokens))
                                onEvent(.usage(tokens: r.tokens, costUSD: r.costUSD, estimated: r.estimated))
                                return WorkerResult(order: thisOrder, role: role.name, text: r.text, tokens: r.tokens, cost: r.costUSD)
                            } catch {
                                if Task.isCancelled { return nil }
                                // A stale login surfaces as a typed auth error → tell the UI which
                                // provider to reconnect (one-tap), but ONLY the first time for that
                                // provider so its fanned-out siblings don't each raise the prompt.
                                // Both a fast auth prompt AND a silent stall mean "this provider
                                // won't answer" — trip the gate so siblings skip, and surface
                                // Reconnect once per provider.
                                if case .authRequired(let p)? = (error as? OneShotError) {
                                    if await authGate.trip(p) { onEvent(.authRequired(p)) }
                                } else if case .stalled(let p)? = (error as? OneShotError) {
                                    if await authGate.trip(p) { onEvent(.authRequired(p)) }
                                }
                                // Report the failure (logged + marked done on the main
                                // actor via .roleFailed) and keep the other workers going.
                                // runStep already re-labels the error with role/provider.
                                let why = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
                                DiagnosticsLog.record("meta FAIL #\(thisOrder + 1): \(role.name) — \(why)")
                                onEvent(.roleFailed(role: role.name, message: why))
                                return nil
                            }
                        }
                    }
                }
                var out: [WorkerResult] = []
                for await r in group { if let r { out.append(r) } }
                return out.sorted { $0.order < $1.order }
            }

            if Task.isCancelled { return nil }
            // Every worker failed → nothing to synthesize. Fail with actionable guidance
            // instead of feeding the orchestrator an empty result set.
            if collected.isEmpty {
                if !staleProviders.isEmpty {
                    let names = staleProviders.map(\.displayName).sorted().joined(separator: ", ")
                    onEvent(.failed("No agent could run — \(names) needs you to sign in again. Reconnect it in Providers, then retry."))
                } else {
                    onEvent(.failed("Every agent failed to produce a result — check each provider is signed in and supports its model (see the diagnostics log), then retry."))
                }
                return nil
            }
            let results: [(role: String, text: String)] = collected.map { ($0.role, $0.text) }
            // 3) SYNTHESIZE — the orchestrator combines everything.
            onEvent(.phase("synthesize"))
            onEvent(.roleStarted(role: orchestrator.name, provider: orchestrator.provider, model: orchModel))
            let synth = try await runStep(runner, role: orchestrator.name, provider: orchestrator.provider,
                                          model: orchModel, prompt: synthesisPrompt(task: task, results: results), cwd: cwd,
                                          onActivity: activity(orchestrator.name))
            onEvent(.roleFinished(role: orchestrator.name, tokens: synth.tokens))
            onEvent(.usage(tokens: synth.tokens, costUSD: synth.costUSD, estimated: synth.estimated))
            onEvent(.assistantText(synth.text))
            onEvent(.finished)
            return synth.text
        } catch {
            // A cancelled turn shouldn't surface as an error.
            if Task.isCancelled || error is CancellationError { return nil }
            // A stale login (orchestrator's own provider) → offer a one-tap Reconnect.
            if case .authRequired(let p)? = (error as? OneShotError) {
                onEvent(.authRequired(p))
            }
            let msg = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
            onEvent(.failed(msg))
            return nil
        }
    }
}
