//
//  TeamImprover.swift
//  StrategyForge
//
//  Recursive AUTO-improvement (RAI, not RSI): a convergent loop that pulls a team toward
//  its own spec. It derives probes from the team's spec + real usage (EvalRunner), runs
//  them against the team judged by the INDEPENDENT read-only judge, and for each round of
//  failures asks an independent editor to propose ONE minimal lever change to a role
//  (tighten/add a rule to its system prompt, or swap its model), applies it, and re-runs —
//  until the suite clears its threshold or a hard iteration brake trips.
//
//  Pure helpers (edit prompt, tolerant parse, apply) are static and tested directly;
//  `improve` wires them to injected runners (real CLI, or a mock in tests) — the same seam
//  MetaOrchestrator / EvalRunner use. The editor is a different concern from the maker:
//  it never touches files, it only proposes a spec edit a human can review before applying.
//

import Foundation

/// One convergent edit the improver makes to a role, with the reasoning behind it.
struct TeamEdit: Sendable, Equatable, Identifiable {
    enum Field: String, Sendable, Equatable { case systemPrompt, model, description }
    var id = UUID()
    var roleName: String
    var field: Field
    var before: String
    var after: String
    var rationale: String

    static func == (l: TeamEdit, r: TeamEdit) -> Bool {
        l.roleName == r.roleName && l.field == r.field && l.after == r.after && l.rationale == r.rationale
    }
}

/// Progress of an auto-improvement run, for the UI.
enum ImproveEvent: Sendable {
    case status(String)                              // a human line ("Deriving probes from usage…")
    case probes(Int)                                 // the suite has N probes
    case iteration(Int, passed: Int, total: Int)     // round i finished with this pass count
    case applied(TeamEdit)                           // an edit was applied this round
    case finished(passRate: Double, iterations: Int)
    case failed(String)
}

/// The result of an auto-improvement run.
struct ImproveOutcome: Sendable {
    var improvedTeam: Strategy
    var edits: [TeamEdit]
    var startPassRate: Double
    var endPassRate: Double
    var iterations: Int
    var finalRun: EvalRun
}

enum TeamImprover {

    // MARK: - Edit proposal (pure prompt + parse + apply)

    /// Compact roster the editor edits against: each role's name, provider·model and its
    /// current system prompt (the levers it can touch).
    static func roster(_ team: Strategy) -> String {
        team.roles.map { r in
            let m = MetaOrchestrator.modelID(for: r)
            let sp = r.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            - \(r.name) [\(r.isOrchestrator ? "orchestrator" : "worker")] · \(r.provider.displayName)·\(m.isEmpty ? "default" : m)
              system prompt: \(sp.isEmpty ? "(none)" : sp)
            """
        }.joined(separator: "\n")
    }

    /// Ask an independent editor for ONE minimal lever change that fixes the most failures,
    /// convergent to the team's purpose (never scope-creep the spec).
    static func editPrompt(team: Strategy, failures: [(scenario: EvalScenario, reason: String)]) -> String {
        let fails = failures.prefix(12).map {
            "- PROMPT: \($0.scenario.prompt)\n  EXPECTED: \($0.scenario.expectation)\n  WHY IT FAILED: \($0.reason)"
        }.joined(separator: "\n")
        return """
        You are improving an AI agent team so it matches its own spec. This is CONVERGENT:
        make the smallest change that fixes the most failures below WITHOUT expanding the
        team's purpose. Prefer tightening or adding ONE rule to a role's system prompt; only
        change a role's model when the failures are clearly a capability problem.

        TEAM PURPOSE:
        \(team.name) — \(team.description)

        ROLES (the only things you may edit):
        \(roster(team))

        FAILING PROBES (each with the judge's reason):
        \(fails)

        Choose ONE role and ONE field to change. For "systemPrompt" return the FULL new
        system prompt (the current one plus your minimal edit), not a diff. For "model"
        return a model id valid for that role's provider.

        Respond with ONLY this JSON, no prose, no code fences:
        {"role":"<role name>","field":"systemPrompt|model|description","value":"<the full new value>","rationale":"<one sentence: what you changed and why>"}
        """
    }

    /// Tolerant parse of the editor's JSON into a `TeamEdit`, resolving the role by loose
    /// name match and capturing the current value as `before`. Returns nil when it can't be
    /// applied (no such role, empty/again-equal value, unknown field) — never a no-op edit.
    static func parseEdit(_ text: String, team: Strategy) -> TeamEdit? {
        guard let obj = ModelJSON.firstObject(in: text) else { return nil }
        guard let roleRaw = (obj["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let fieldRaw = (obj["field"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let field = TeamEdit.Field(rawValue: fieldRaw),
              let value = (obj["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        // Resolve to a real role (loose match, then exact).
        guard let role = team.roles.first(where: { AgentNameMatcher.titlesMatch($0.name, roleRaw) })
            ?? team.roles.first(where: { $0.name.caseInsensitiveCompare(roleRaw) == .orderedSame }) else { return nil }
        let before: String
        switch field {
        case .systemPrompt: before = role.systemPrompt
        case .description:  before = role.description
        case .model:        before = MetaOrchestrator.modelID(for: role)
        }
        guard before.trimmingCharacters(in: .whitespacesAndNewlines) != value else { return nil }   // no-op
        let rationale = (obj["rationale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TeamEdit(roleName: role.name, field: field, before: before, after: value,
                        rationale: rationale.isEmpty ? "Tightened to fix failing probes." : rationale)
    }

    /// Apply an edit to a COPY of the team (never mutates the input).
    static func apply(_ edit: TeamEdit, to team: Strategy) -> Strategy {
        var out = team
        guard let i = out.roles.firstIndex(where: { $0.name == edit.roleName }) else { return out }
        switch edit.field {
        case .systemPrompt: out.roles[i].systemPrompt = edit.after
        case .description:  out.roles[i].description = edit.after
        case .model:
            if out.roles[i].provider == .claude {
                if let m = ClaudeModel(rawValue: edit.after) { out.roles[i].model = m }
            } else {
                out.roles[i].providerModelID = edit.after
            }
        }
        return out
    }

    // MARK: - The convergent loop

    /// Improve `team` toward its spec. Derives a suite from spec + `usageExcerpts` when the
    /// team has none, runs it (judged independently), and edits one lever per round until it
    /// clears the threshold or `maxIterations` trips. `judgeRunner` (Claude, read-only) both
    /// judges and proposes edits — an independent voice from the team it grades.
    static func improve(team input: Strategy, usageExcerpts: [String] = [], maxIterations: Int = 5,
                        answerRunner: OneShotRunner, judgeRunner: OneShotRunner, cwd: String? = nil,
                        onEvent: @escaping @Sendable (ImproveEvent) -> Void) async -> ImproveOutcome? {
        guard input.orchestrator != nil else { onEvent(.failed("This team has no orchestrator.")); return nil }
        var team = input

        // 1) Ensure a probe suite — derive from spec + real usage when absent.
        var suite = team.evalSuite ?? EvalSuite()
        if suite.scenarios.isEmpty {
            onEvent(.status(usageExcerpts.isEmpty ? "Deriving probes from the team's spec…"
                                                  : "Deriving probes from real usage…"))
            let scenarios = await EvalRunner.generate(team: team, count: 10, usageExcerpts: usageExcerpts,
                                                      runner: judgeRunner, cwd: cwd)
            suite.scenarios = scenarios
            team.evalSuite = suite
        }
        guard !suite.scenarios.isEmpty else { onEvent(.failed("Couldn't derive any probes to improve against.")); return nil }
        onEvent(.probes(suite.scenarios.count))

        // 2) Baseline run.
        if Task.isCancelled { return nil }
        var run = await EvalRunner.run(team: team, suite: suite, cwd: cwd,
                                       answerRunner: answerRunner, judgeRunner: judgeRunner)
        let startRate = run.passRate
        onEvent(.iteration(0, passed: run.passed, total: run.total))

        // 3) Edit one lever per round until the suite passes or the brake trips.
        var edits: [TeamEdit] = []
        var iteration = 0
        let orch = team.orchestrator!
        while iteration < maxIterations, !run.meetsThreshold {
            if Task.isCancelled { break }
            iteration += 1
            let failing: [(EvalScenario, String)] = run.results.compactMap { r in
                guard !r.effectivePassed, let s = suite.scenarios.first(where: { $0.id == r.scenarioID }) else { return nil }
                return (s, r.reason)
            }
            guard !failing.isEmpty else { break }
            onEvent(.status("Round \(iteration): proposing a fix for \(failing.count) failing probe(s)…"))
            let editText = (try? await judgeRunner.run(prompt: editPrompt(team: team, failures: failing),
                                                       provider: .claude, model: "", cwd: cwd))?.text ?? ""
            guard let edit = parseEdit(editText, team: team) else {
                onEvent(.status("No actionable edit this round — stopping."))
                break
            }
            team = apply(edit, to: team)
            edits.append(edit)
            onEvent(.applied(edit))
            if Task.isCancelled { break }
            run = await EvalRunner.run(team: team, suite: suite, cwd: cwd,
                                       answerRunner: answerRunner, judgeRunner: judgeRunner)
            onEvent(.iteration(iteration, passed: run.passed, total: run.total))
            _ = orch   // (kept for future per-round orchestrator-model checks)
        }

        // Persist the final run as the suite's baseline so a later manual run diffs against it.
        suite.baseline = run.baselineMap
        team.evalSuite = suite
        onEvent(.finished(passRate: run.passRate, iterations: iteration))
        return ImproveOutcome(improvedTeam: team, edits: edits, startPassRate: startRate,
                              endPassRate: run.passRate, iterations: iteration, finalRun: run)
    }
}
