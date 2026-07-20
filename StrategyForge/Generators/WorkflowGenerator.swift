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

    /// The dynamic-workflow program for a team, or nil for a solo team (no graph).
    static func workflow(for strategy: Strategy) -> String? {
        let workers = strategy.subagentRoles.filter { Strategy.isValidRoleName($0.name) }
        guard !workers.isEmpty, let orchestrator = strategy.orchestrator else { return nil }

        let name = slug(strategy)
        let description = jsLine(strategy.description.isEmpty ? strategy.name : strategy.description)

        var out = "\(managedSignature) for the team \"\(jsLine(strategy.name))\".\n"
        out += "// Run it with Claude Code: pass your task as args. Regenerated on Generate.\n\n"

        // meta — a pure literal, phase titles matched in the body.
        out += "export const meta = {\n"
        out += "  name: '\(name)',\n"
        out += "  description: '\(description)',\n"
        out += "  phases: [{ title: 'Plan' }, { title: 'Work' }, { title: 'Synthesize' }],\n"
        out += "}\n\n"

        out += "// The task comes in as `args` (falls back to the team's purpose).\n"
        out += "const task = (typeof args === 'string' && args) ? args : `\(jsTemplate(strategy.description))`\n\n"

        // Plan.
        out += "phase('Plan')\n"
        out += "const plan = await agent(`\(jsTemplate(planPrompt(orchestrator)))\n\nTASK:\n${task}`, "
        out += "{ label: 'plan' })\n\n"

        // Work — one teammate per parallel branch.
        out += "phase('Work')\n"
        out += "const results = await parallel([\n"
        for w in workers {
            let model = w.model.rawValue
            out += "  () => agent(`\(jsTemplate(workerPrompt(w)))\n\nTASK:\n${task}\n\nPLAN:\n${plan}`, "
            out += "{ label: '\(jsLine(w.name))', phase: 'Work', model: '\(model)' }),\n"
        }
        out += "])\n\n"

        // Synthesize.
        out += "phase('Synthesize')\n"
        out += "const final = await agent(`\(jsTemplate(synthesisPrompt))\n\n"
        out += "TASK:\n${task}\n\nTEAMMATE RESULTS:\n${results.filter(Boolean).join('\\n\\n---\\n\\n')}`, "
        out += "{ label: 'synthesize' })\n\n"
        out += "return final\n"
        return out
    }

    // MARK: - Prompts (pure)

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

    private static var synthesisPrompt: String {
        "You are the orchestrator. Combine the teammates' results into one coherent, "
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
