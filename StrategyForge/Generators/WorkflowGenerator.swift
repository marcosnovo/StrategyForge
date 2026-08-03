//
//  WorkflowGenerator.swift
//  StrategyForge
//
//  Turns a team (Strategy) into a Claude Code DYNAMIC WORKFLOW — "a workflow moves the
//  plan into code" (the graph-engineering piece). The team's topology becomes a runnable
//  program a background runtime executes: the orchestrator plans, teammates run in
//  PARALLEL, then the orchestrator synthesizes — giving a designed team a deterministic
//  runtime (parallel branches, structured phases) instead of only turn-by-turn delegation.
//
//  Pure + testable (no disk). Emitted to `.claude/workflows/<slug>.mjs`, where Claude Code
//  discovers saved workflows. Only meaningful for a team with teammates (a solo agent is
//  just one prompt, not a graph).
//

import Foundation

/// The SHAPE the generated workflow takes for a team — the graph before it's text.
///
/// Extracted so it has exactly one definition: `WorkflowGenerator` emits it as JavaScript
/// and `GraphCostLens` prices it. If the two derived their own shapes independently, the
/// cost lens would eventually describe a graph the generator no longer emits.
enum WorkflowShape: Equatable {
    /// One parallel Work branch per producer role, optionally gated by a Verify phase.
    case roleParallel(orchestrator: AgentRole, workers: [AgentRole], verifier: AgentRole?)
    /// One agent per unit of work: a scout discovers the item list, then a pipeline runs
    /// (and optionally verifies) each item. `instances` is the scouted fan-out width.
    case itemFanout(orchestrator: AgentRole, worker: AgentRole, verifier: AgentRole?, instances: Int)

    var verifier: AgentRole? {
        switch self {
        case let .roleParallel(_, _, v), let .itemFanout(_, _, v, _): return v
        }
    }

    /// How many agents run CONCURRENTLY at the widest point — the whole reason a workflow
    /// beats a chat. A width of 1 means the "graph" is a straight line.
    var parallelWidth: Int {
        switch self {
        case let .roleParallel(_, workers, _): return max(1, workers.count)
        case let .itemFanout(_, _, _, n):      return max(1, n)
        }
    }
}

enum WorkflowGenerator {

    /// Repo-relative directory generated workflows live in.
    static let workflowsDirectory = ".claude/workflows"

    /// Signature marking a workflow file WE generated — pruning only ever touches
    /// files carrying it, so hand-written workflows are never removed.
    static let managedSignature = "// coral: generated dynamic workflow"

    /// Repo-relative path for a team's generated workflow.
    static func fileName(for strategy: Strategy) -> String {
        "\(workflowsDirectory)/\(slug(strategy)).mjs"
    }

    /// A stable, filesystem-safe slug from the team name (falls back to "team").
    static func slug(_ strategy: Strategy) -> String {
        let base = strategy.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(base).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "team" : collapsed
    }

    /// The graph a team compiles to, or nil for a solo team (one prompt isn't a graph).
    /// Pure — the single source of truth both the emitter and the cost lens read.
    static func shape(for strategy: Strategy) -> WorkflowShape? {
        let teammates = strategy.subagentRoles.filter { Strategy.isValidRoleName($0.name) }
        guard !teammates.isEmpty, let orchestrator = strategy.orchestrator else { return nil }

        // Split the roster into PRODUCERS (do the work in parallel) and REVIEWERS (gate the
        // edge). A reviewer that fanned out alongside the producers would just be a fourth
        // producer — the graph-engineering piece's "agrees with itself in a different font".
        // Moving it to a dedicated Verify phase makes it an independent node on a fresh
        // context, checking the producers' output before it flows to synthesis.
        let reviewers = teammates.filter { $0.role == .reviewer }
        let producers = teammates.filter { $0.role != .reviewer }
        // If the team is ALL reviewers (unusual), treat them as producers so it still runs.
        let workers = producers.isEmpty ? teammates : producers
        let verifier = producers.isEmpty ? nil : reviewers.first

        // A fan-out of identical workers (all producers are plain workers, ≥2 instances via
        // the role's `count`) is a "one agent per unit of work" job — a codebase audit, a
        // migration, a sweep. Emit the canonical item fan-out (scout the work-list → pipeline
        // one agent per item, verifying each as it lands → synthesize) instead of one branch
        // per role. This is the migration/graph pattern.
        let workerInstances = producers.filter { $0.role == .worker }.map { max(1, $0.count) }.reduce(0, +)
        if !producers.isEmpty, producers.allSatisfy({ $0.role == .worker }), workerInstances >= 2 {
            return .itemFanout(orchestrator: orchestrator, worker: producers[0],
                               verifier: verifier, instances: workerInstances)
        }
        return .roleParallel(orchestrator: orchestrator, workers: workers, verifier: verifier)
    }

    /// The dynamic-workflow program for a team, or nil for a solo team (no graph).
    static func workflow(for strategy: Strategy) -> String? {
        switch shape(for: strategy) {
        case .none:
            return nil
        case let .itemFanout(orchestrator, worker, verifier, _):
            return itemFanoutWorkflow(strategy: strategy, orchestrator: orchestrator,
                                      worker: worker, verifier: verifier)
        case let .roleParallel(orchestrator, workers, verifier):
            return roleParallelWorkflow(strategy: strategy, orchestrator: orchestrator,
                                        workers: workers, verifier: verifier)
        }
    }

    /// One parallel Work branch per producer role: plan → parallel work → (verify) →
    /// synthesize. The classic diamond.
    static func roleParallelWorkflow(strategy: Strategy, orchestrator: AgentRole,
                                     workers: [AgentRole], verifier: AgentRole?) -> String {
        let hasVerify = verifier != nil

        let name = slug(strategy)
        let description = jsLine(strategy.description.isEmpty ? strategy.name : strategy.description)

        var out = "\(managedSignature) for the team \"\(jsLine(strategy.name))\".\n"
        out += "// Run it with Claude Code: pass your task as args. Regenerated on Generate.\n"
        // The graph-engineering caution: a workflow fans out real agents, so it costs
        // meaningfully more than one chat and wants a human watching. Scope the task first.
        out += "// NOTE: this fans out parallel agents — it costs more than a single session and\n"
        out += "// should be supervised. Start with a scoped task, watch usage, then widen.\n\n"

        // meta — a pure literal, phase titles matched in the body. Verify only when the
        // team has a reviewer to gate the edge with.
        let phases = hasVerify
            ? "[{ title: 'Plan' }, { title: 'Work' }, { title: 'Verify' }, { title: 'Synthesize' }]"
            : "[{ title: 'Plan' }, { title: 'Work' }, { title: 'Synthesize' }]"
        out += "export const meta = {\n"
        out += "  name: '\(name)',\n"
        out += "  description: '\(description)',\n"
        out += "  phases: \(phases),\n"
        out += "}\n\n"

        out += "// The task comes in as `args` (falls back to the team's purpose).\n"
        out += "const task = (typeof args === 'string' && args) ? args : `\(jsTemplate(strategy.description))`\n\n"

        // Plan.
        out += "phase('Plan')\n"
        out += "const plan = await agent(`\(jsTemplate(planPrompt(orchestrator)))\n\nTASK:\n${task}`, "
        out += "{ label: 'plan' })\n\n"

        // Work — one teammate per parallel branch. A producer that EDITS files (not
        // read-only) runs in its own git worktree so parallel writers can't overwrite each
        // other — the Bun-port lesson (isolate the workers, don't just prompt them nicely).
        // A role with `count > 1` is N teammates, so it becomes N concurrent branches —
        // emitting one branch for a role the user asked to triple would quietly narrow the
        // graph back towards a line (and disagree with what the cost lens prices).
        out += "phase('Work')\n"
        out += "const results = await parallel([\n"
        for w in workers {
            let model = w.model.rawValue
            let isolation = w.sandbox.isolatesInWorktree(for: w.role) ? ", isolation: 'worktree'" : ""
            for instance in 1...max(1, w.count) {
                let label = w.count > 1 ? "\(jsLine(w.name))-\(instance)" : jsLine(w.name)
                out += "  () => agent(`\(jsTemplate(workerPrompt(w)))\n\nTASK:\n${task}\n\nPLAN:\n${plan}`, "
                out += "{ label: '\(label)', phase: 'Work', model: '\(model)'\(isolation) }),\n"
            }
        }
        out += "])\n\n"

        // Verify — an INDEPENDENT node on a fresh context checks each producer's finding
        // against real evidence before it flows downstream (article: gate the edge).
        var synthInput = "results"
        if let verifier {
            let model = verifier.model.rawValue
            out += "phase('Verify')\n"
            out += "const verified = await parallel(results.filter(Boolean).map((r, i) => () => "
            out += "agent(`\(jsTemplate(verifyPrompt(verifier)))\n\nTASK:\n${task}\n\nWORK TO VERIFY:\n${r}`, "
            out += "{ label: 'verify:' + i, phase: 'Verify', model: '\(model)' })))\n\n"
            synthInput = "verified"
        }

        // Synthesize.
        out += "phase('Synthesize')\n"
        out += "const final = await agent(`\(jsTemplate(synthesisPrompt))\n\n"
        out += "TASK:\n${task}\n\n\(hasVerify ? "VERIFIED FINDINGS" : "TEAMMATE RESULTS"):\n${\(synthInput).filter(Boolean).join('\\n\\n---\\n\\n')}`, "
        out += "{ label: 'synthesize' })\n\n"
        out += "return final\n"
        return out
    }

    /// The item fan-out workflow (article's canonical shape): a scout discovers the work-list,
    /// then a `pipeline` runs one worker agent per item and — when the team has a reviewer —
    /// verifies each finding as soon as it lands, before a final synthesis. Resumable/wide by
    /// construction; the fleet moves in waves. Used for fan-out-of-identical-worker teams.
    static func itemFanoutWorkflow(strategy: Strategy, orchestrator: AgentRole,
                                   worker: AgentRole, verifier: AgentRole?) -> String {
        let name = slug(strategy)
        let description = jsLine(strategy.description.isEmpty ? strategy.name : strategy.description)
        let workerModel = worker.model.rawValue
        let isolation = worker.sandbox.isolatesInWorktree(for: worker.role) ? ", isolation: 'worktree'" : ""
        let hasVerify = verifier != nil

        var out = "\(managedSignature) for the team \"\(jsLine(strategy.name))\" — ITEM FAN-OUT.\n"
        out += "// One agent per unit of work (file/item): scout the list, fan out, verify each.\n"
        out += "// NOTE: this can fan out to many agents — it costs more than a single session and\n"
        out += "// should be supervised. The scout starts scoped (≤50 items); widen once it behaves.\n\n"

        let phases = hasVerify
            ? "[{ title: 'Scout' }, { title: 'Work' }, { title: 'Verify' }, { title: 'Synthesize' }]"
            : "[{ title: 'Scout' }, { title: 'Work' }, { title: 'Synthesize' }]"
        out += "export const meta = {\n  name: '\(name)',\n  description: '\(description)',\n  phases: \(phases),\n}\n\n"

        out += "// The task/target comes in as `args` (falls back to the team's purpose).\n"
        out += "const task = (typeof args === 'string' && args) ? args : `\(jsTemplate(strategy.description))`\n\n"

        // Scout — discover the work-list. Returns a JSON array of items (parsed tolerantly).
        out += "phase('Scout')\n"
        out += "const scoutText = await agent(`\(jsTemplate(scoutPrompt(orchestrator)))\n\nTASK:\n${task}`, "
        out += "{ label: 'scout' })\n"
        out += "let items = []\n"
        out += "try { items = JSON.parse((scoutText.match(/\\[[\\s\\S]*\\]/) || ['[]'])[0]) } catch { items = [] }\n"
        out += "items = items.filter(x => typeof x === 'string' && x.trim()).slice(0, 50)\n"
        out += "log(`${items.length} item(s) to process`)\n\n"

        // Work + Verify — pipeline: each item flows through work → verify independently, no
        // barrier, so a fast item verifies while a slow one is still being worked.
        out += "phase('Work')\n"
        if hasVerify, let verifier {
            let vModel = verifier.model.rawValue
            out += "const findings = await pipeline(items,\n"
            out += "  (item) => agent(`\(jsTemplate(itemWorkerPrompt(worker)))\n\nTASK:\n${task}\n\nITEM:\n${item}`, "
            out += "{ label: 'work:' + item, phase: 'Work', model: '\(workerModel)'\(isolation) }),\n"
            out += "  (result, item) => agent(`\(jsTemplate(verifyPrompt(verifier)))\n\nITEM:\n${item}\n\nWORK TO VERIFY:\n${result}`, "
            out += "{ label: 'verify:' + item, phase: 'Verify', model: '\(vModel)' })\n"
            out += ")\n\n"
        } else {
            out += "const findings = await parallel(items.map((item) => () => "
            out += "agent(`\(jsTemplate(itemWorkerPrompt(worker)))\n\nTASK:\n${task}\n\nITEM:\n${item}`, "
            out += "{ label: 'work:' + item, phase: 'Work', model: '\(workerModel)'\(isolation) })))\n\n"
        }

        // Synthesize — one report from the (verified) findings, not N separate chats.
        out += "phase('Synthesize')\n"
        out += "const final = await agent(`\(jsTemplate(synthesisPrompt))\n\n"
        out += "TASK:\n${task}\n\n\(hasVerify ? "VERIFIED FINDINGS" : "FINDINGS"):\n${findings.filter(Boolean).join('\\n\\n---\\n\\n')}`, "
        out += "{ label: 'synthesize' })\n\n"
        out += "return final\n"
        return out
    }

    // MARK: - Prompts (pure)

    /// The scout node's prompt: discover the independent units of work and return them as a
    /// JSON array (files/items/crates), so the pipeline can fan out one agent per item.
    private static func scoutPrompt(_ orchestrator: AgentRole) -> String {
        let persona = orchestrator.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = persona.isEmpty ? "You are the orchestrator of a team of AI agents." : persona
        return lead + "\nDiscover the independent units of work for this task — the files/items an "
            + "agent should each handle on its own. Prefer a deterministic listing (a glob, a git "
            + "ls-files, a script). Return ONLY a JSON array of strings (the item identifiers), "
            + "nothing else. Start scoped: at most 50 items."
    }

    /// The per-item worker prompt: handle exactly ONE item and report its finding.
    private static func itemWorkerPrompt(_ role: AgentRole) -> String {
        let persona = role.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = persona.isEmpty
            ? "You are \(role.name), a \(role.role.displayName.lowercased()) on the team."
            : persona
        return lead + "\nYou handle exactly ONE item (below). Do the task for just that item and "
            + "report your finding concisely. If you can't do it confidently, flag it with a clear reason."
    }

    private static func planPrompt(_ orchestrator: AgentRole) -> String {
        let persona = orchestrator.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = persona.isEmpty ? "You are the orchestrator of a team of AI agents." : persona
        return lead + "\nBreak the task into focused, parallel-friendly pieces the teammates can each take. "
            + "Write a short plan the teammates will read."
    }

    private static func workerPrompt(_ role: AgentRole) -> String {
        let persona = role.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return persona.isEmpty
            ? "You are \(role.name), a \(role.role.displayName.lowercased()) on the team. Do your part of the task and report back concisely."
            : persona
    }

    /// The verifier node's prompt: it did NOT produce the work and runs on a fresh context,
    /// so it checks a real signal (does the test pass, is the claim grounded) rather than
    /// "did the agent say it's done" — the graph-engineering piece's anti-"agrees-with-itself".
    private static func verifyPrompt(_ reviewer: AgentRole) -> String {
        let persona = reviewer.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = persona.isEmpty
            ? "You are an INDEPENDENT verifier. You did not do this work."
            : persona
        return lead + "\nVerify the work below against real evidence — run/inspect the actual "
            + "signal (a test that PASSED, a claim that's grounded), not whether it claims to be "
            + "done. Return the finding only if it holds; otherwise state exactly what fails."
    }

    private static var synthesisPrompt: String {
        "You are the orchestrator. Combine the verified results into one coherent, "
            + "actionable final answer. Resolve conflicts, remove redundancy."
    }

    // MARK: - JS escaping

    /// Escape a value for a SINGLE-LINE JS context (single quotes / comments): flatten
    /// newlines and escape quotes/backslashes.
    private static func jsLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Escape a value for embedding inside a JS TEMPLATE literal (backticks): escape
    /// backslash, backtick, and `${` so the persona text can't break out or interpolate.
    private static func jsTemplate(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
    }
}
