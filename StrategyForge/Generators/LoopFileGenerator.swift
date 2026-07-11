//
//  LoopFileGenerator.swift
//  StrategyForge
//
//  Pure, testable generation of a loop's files (LOOP.md, STATE.md, the
//  independent verifier subagent and loop.sh) from a LoopPlan. No disk access —
//  `LoopWriter` below does the writing, mirroring `StrategyWriter`.
//

import Foundation

enum LoopFileGenerator {

    /// All files for a plan, as pure data, so the UI can preview exact contents
    /// before anything touches disk. loop.sh uses the placeholder binary `claude`;
    /// `LoopWriter` swaps in the user's configured binary when writing.
    static func generate(for plan: LoopPlan) -> [GeneratedFile] {
        var files: [GeneratedFile] = [
            GeneratedFile(relativePath: "LOOP.md", contents: loopMd(plan)),
        ]
        if plan.memoryEnabled {
            files.append(GeneratedFile(relativePath: "STATE.md", contents: stateMd()))
        }
        if plan.verifierEnabled {
            files.append(GeneratedFile(relativePath: ".claude/agents/loop-verifier.md",
                                       contents: verifierMd(plan)))
        }
        files.append(GeneratedFile(relativePath: "loop.sh", contents: loopSh(plan)))
        return files
    }

    /// The command that starts the loop. A goal loop runs interactively under the
    /// worker's model (the `/goal` line is a human instruction for the session);
    /// every other kind runs through the generated script.
    static func launchCommand(for plan: LoopPlan, binary: String) -> String {
        switch plan.kind {
        case .goalBased:
            let goal = flat(plan.goal.isEmpty ? "<goal>" : plan.goal)
            return "\(binary) --model \(plan.workerModel.rawValue)\n"
                + "# then inside the session: /goal \(goal) — max \(turns(plan)) turns"
        case .turnBased, .timeBased, .proactive:
            return "./loop.sh"
        }
    }

    // MARK: - LOOP.md (the spec the loop re-reads every iteration)

    private static func loopMd(_ plan: LoopPlan) -> String {
        let title = displayName(plan)
        let goal = plan.goal.trimmingCharacters(in: .whitespacesAndNewlines)

        var out = "# \(title)\n\n"
        out += "\(kindTitle(plan.kind)) — `\(plan.kind.flow)`\n\n"

        out += "## Goal\n\n"
        out += (plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (goal.isEmpty ? "(describe the mission)" : goal)
                : flat(plan.name)) + "\n\n"

        out += "## Done when\n\n"
        out += (goal.isEmpty ? "(a condition that can be checked mechanically — tests, grep, build output; not vibes)" : goal) + "\n\n"

        out += "## Never touch\n\n"
        out += bulleted(plan.neverTouch, ifEmpty: "- (nothing listed)") + "\n\n"

        out += "## Stop if\n\n"
        out += "- More than \(turns(plan)) turns have run — the emergency brake.\n"
        let extra = bulleted(plan.stopIf, ifEmpty: "")
        if !extra.isEmpty { out += extra + "\n" }
        out += "- Anything under \"Never touch\" would need to change.\n\n"

        out += "## How this loop runs\n\n"
        out += howItRuns(plan)
        if plan.memoryEnabled {
            out += "\n**Memory rule:** Read STATE.md before starting. Update STATE.md before finishing.\n"
        }
        return out
    }

    private static func howItRuns(_ plan: LoopPlan) -> String {
        let launch = launchCommand(for: plan, binary: "claude")
        switch plan.kind {
        case .turnBased:
            return """
            One round per run: you prompt, it works, an independent check reports, \
            and it stops so you steer the next round.

            ```
            \(launch)
            ```
            """
        case .goalBased:
            return """
            The loop takes one focused step per turn, then an independent verifier \
            judges the result against "Done when". It repeats until PASS or the \
            turn limit. Run `./loop.sh`, or drive it interactively:

            ```
            \(launch)
            ```
            """
        case .timeBased:
            return """
            One pass per firing; cron does the waiting. Install with `crontab -e`:

            ```
            \(cronLine(plan))
            ```
            """
        case .proactive:
            return """
            Fires on an event with no human online, so every result is reviewed \
            before anyone trusts it. Hook your event source to:

            ```
            \(launch)
            ```
            """
        }
    }

    // MARK: - STATE.md (the memory template)

    private static func stateMd() -> String {
        """
        # STATE.md — loop memory

        <!-- The loop reads this file at the start of every run and updates it at the end, so run N+1 resumes instead of restarting. -->

        ## Verified facts

        <!-- Things proven true by running or checking — never assumptions. -->

        ## General rules

        <!-- Standing constraints discovered along the way (e.g. "never regenerate fixtures"). -->

        ## Open failures (investigate next session)

        <!-- Known-broken things with repro notes, so the next run starts here. -->

        ## Lessons learned

        <!-- Mistakes made once that must not repeat. -->

        ## Last session

        <!-- One paragraph: what the previous run did and where it stopped. -->
        """
    }

    // MARK: - Verifier subagent

    private static func verifierMd(_ plan: LoopPlan) -> String {
        // Read-only tools + Bash (to run tests/linters), never Write/Edit: the
        // verifier judges, it does not fix.
        let tools = (Constants.readOnlyTools + ["Bash"]).joined(separator: ", ")
        let description = "Independent verifier for the \(displayName(plan)) loop. "
            + "Must be invoked after EVERY work iteration to judge the result against the goal in LOOP.md."

        var fm = "---\n"
        fm += "name: loop-verifier\n"
        fm += "description: \(escapedScalar(description))\n"
        fm += "tools: \(tools)\n"
        fm += "model: \(plan.verifierModel.rawValue)\n"
        fm += "\(AgentFileGenerator.managedSignature)\n"
        fm += "---\n"

        let body = """

        You are an independent verifier. Read LOOP.md. Judge ONLY the artifact against
        '## Done when'. You did not write this work; do not trust its reasoning.

        Reply with exactly `VERDICT: PASS` or `VERDICT: FAIL` on the first line, then
        bullet reasons. Never propose fixes. Never be polite.
        """
        return fm + body + "\n"
    }

    // MARK: - loop.sh (per-kind runner)

    /// Placeholder binary used inside loop.sh; `LoopWriter` substitutes the real one.
    static let binaryPlaceholderLine = "BINARY=\"claude\""

    private static func loopSh(_ plan: LoopPlan) -> String {
        switch plan.kind {
        case .goalBased: return goalScript(plan)
        case .turnBased: return turnScript(plan)
        case .timeBased: return timeScript(plan)
        case .proactive: return proactiveScript(plan)
        }
    }

    /// The one-step work prompt shared by every script (references LOOP.md instead
    /// of inlining user text, so nothing needs shell escaping).
    private static func workPrompt(_ plan: LoopPlan, verb: String) -> String {
        let read = plan.memoryEnabled ? "Read LOOP.md and STATE.md." : "Read LOOP.md."
        let close = plan.memoryEnabled ? " Update STATE.md before finishing." : ""
        return "\(read) \(verb) Respect '## Never touch' and '## Stop if'.\(close)"
    }

    /// The verify call: through the independent subagent when enabled, else a
    /// weaker self-judgement (still better than nothing for a runnable script).
    private static func verifyCommand(_ plan: LoopPlan, capture: Bool) -> String {
        let prompt = plan.verifierEnabled
            ? "Use the loop-verifier subagent to judge this repo against '## Done when' in LOOP.md. Reply with its verdict verbatim."
            : "Judge this repo against '## Done when' in LOOP.md. Reply with exactly VERDICT: PASS or VERDICT: FAIL on the first line, then bullet reasons."
        let call = "\"$BINARY\" -p \\\n  \"\(prompt)\""
        return capture ? "VERDICT=\"$(\(call))\"" : call
    }

    private static func goalScript(_ plan: LoopPlan) -> String {
        let judgeComment = plan.verifierEnabled
            ? "# JUDGE — an independent verifier grades the work (the maker never grades itself)."
            : "# JUDGE — no independent verifier configured: the session grades itself (weaker)."
        return """
        #!/bin/bash
        #
        # \(displayName(plan)) — goal loop (Goal → Try → Judge → Done), generated by Coral.
        # Re-runs Claude until the verifier says PASS, or the turn limit — the
        # emergency brake — is reached. Safe to re-run\(plan.memoryEnabled ? ": STATE.md carries memory\n# between runs, so run N+1 resumes instead of restarting." : ".")
        #
        set -euo pipefail

        \(binaryPlaceholderLine)          # the Claude Code CLI
        MAX_TURNS=\(turns(plan))             # emergency brake — hard stop
        MODEL="\(plan.workerModel.rawValue)"  # the worker's model

        for TURN in $(seq 1 "$MAX_TURNS"); do
          echo "== turn $TURN of $MAX_TURNS =="

          # TRY — one focused step toward the goal, never the whole goal at once.
          "$BINARY" -p --model "$MODEL" \\
            "\(workPrompt(plan, verb: "Do the single most useful next step toward '## Done when'."))"

          \(judgeComment)
          \(verifyCommand(plan, capture: true))
          echo "$VERDICT"

          # DONE — stop as soon as the work passes.
          case "$VERDICT" in
            *"VERDICT: PASS"*) echo "Goal met after $TURN turn(s)."; exit 0 ;;
          esac
        done

        echo "Emergency brake: $MAX_TURNS turns without a PASS. Read \(plan.memoryEnabled ? "STATE.md and " : "")LOOP.md and adjust."
        exit 1
        """
    }

    private static func turnScript(_ plan: LoopPlan) -> String {
        """
        #!/bin/bash
        #
        # \(displayName(plan)) — turn-based loop (Prompt → Work → Check → Reply), generated by Coral.
        # ONE round per run: it works, an independent check reports, then it stops
        # so YOU steer the next round. Re-run ./loop.sh for another round.
        #
        set -euo pipefail

        \(binaryPlaceholderLine)
        MODEL="\(plan.workerModel.rawValue)"

        # WORK — one round against the goal in LOOP.md.
        "$BINARY" -p --model "$MODEL" \\
          "\(workPrompt(plan, verb: "Do one round of work toward '## Done when'."))"

        # CHECK — a verdict on where things stand, so your next prompt is informed.
        \(verifyCommand(plan, capture: false))

        # REPLY — over to you: read the verdict, adjust LOOP.md if needed, re-run.
        echo "Round done. Read the verdict above, then re-run ./loop.sh for the next round."
        """
    }

    private static func timeScript(_ plan: LoopPlan) -> String {
        """
        #!/bin/bash
        #
        # \(displayName(plan)) — time-based loop (Interval → Check → React → Wait), generated by Coral.
        # One pass per firing; cron does the waiting. Install with `crontab -e`:
        #
        #   \(cronLine(plan))
        #
        set -euo pipefail

        \(binaryPlaceholderLine)
        MODEL="\(plan.workerModel.rawValue)"

        mkdir -p logs   # cron redirects output here (see the line above)

        # CHECK + REACT — one scheduled pass; WAIT is cron's job.
        "$BINARY" -p --model "$MODEL" \\
          "\(workPrompt(plan, verb: "Run the scheduled check described in '## Goal'; react only if something needs it."))"

        # A verdict on the pass lands in the log, so drift is caught early.
        \(verifyCommand(plan, capture: false))
        """
    }

    private static func proactiveScript(_ plan: LoopPlan) -> String {
        """
        #!/bin/bash
        #
        # \(displayName(plan)) — proactive loop (Event → Route → Work → Review), generated by Coral.
        # Fires on an event, with no human online. Hook it up, for example:
        #   - CI failure : run `./loop.sh "CI failed on $GITHUB_SHA"` as the failure step
        #   - Webhook    : have the receiver run `cd \(plan.repoPath ?? "<repo>") && ./loop.sh "$EVENT_SUMMARY"`
        #
        set -euo pipefail

        \(binaryPlaceholderLine)
        MODEL="\(plan.workerModel.rawValue)"

        EVENT="${1:-unspecified event}"   # a one-line summary of what fired

        # ROUTE + WORK — decide what the event needs, then do exactly that.
        "$BINARY" -p --model "$MODEL" \\
          "\(workPrompt(plan, verb: "An event fired: $EVENT. Route it per '## Goal' and do the work it needs."))"

        # REVIEW — unattended work gets reviewed before anyone trusts it.
        \(verifyCommand(plan, capture: false))
        """
    }

    // MARK: - Helpers

    /// The clamped emergency brake (defense in depth: the editor already clamps).
    private static func turns(_ plan: LoopPlan) -> Int {
        LoopPlan.clampTurns(plan.maxTurns)
    }

    /// Display name for titles/comments — single line, never empty.
    private static func displayName(_ plan: LoopPlan) -> String {
        let flatName = flat(plan.name)
        return flatName.isEmpty ? "Loop" : flatName
    }

    /// Generated files are English (like the other generators); kind names match
    /// the flow literals.
    private static func kindTitle(_ kind: LoopKind) -> String {
        switch kind {
        case .turnBased: return "Turn-based loop"
        case .goalBased: return "Goal loop"
        case .timeBased: return "Time-based loop"
        case .proactive: return "Proactive (event-driven) loop"
        }
    }

    /// The crontab line for a time-based loop. `*/N` is only valid below an hour,
    /// so hourly-and-up cadences switch to an hour schedule.
    private static func cronLine(_ plan: LoopPlan) -> String {
        let m = max(plan.intervalMinutes, 1)
        let schedule: String
        if m < 60 { schedule = "*/\(m) * * * *" }
        else if m % 60 == 0 { schedule = "0 */\(m / 60) * * *" }
        else { schedule = "*/30 * * * *" }
        return "\(schedule) cd \(plan.repoPath ?? "<repo>") && ./loop.sh >> logs/loop.log 2>&1"
    }

    /// Collapse to a single line (user text goes into markdown/comments/YAML).
    private static func flat(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Turn a newline list into markdown bullets; blank lines are dropped.
    private static func bulleted(_ value: String, ifEmpty fallback: String) -> String {
        let lines = value.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return fallback }
        return lines.map { "- \($0)" }.joined(separator: "\n")
    }

    /// YAML-safe rendering of a single-line scalar (same rules as
    /// AgentFileGenerator, whose helper is private).
    private static func escapedScalar(_ value: String) -> String {
        let flatValue = flat(value)
        let needsQuoting = flatValue.contains(":") || flatValue.contains("#")
            || flatValue.hasPrefix("'") || flatValue.hasPrefix("\"")
            || flatValue.hasPrefix(">") || flatValue.hasPrefix("|")
            || flatValue.hasPrefix("-") || flatValue.hasPrefix("[") || flatValue.hasPrefix("{")
        guard needsQuoting else { return flatValue }
        let escaped = flatValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Disk writer

/// Disk I/O layer around the pure generator, mirroring `StrategyWriter`.
///
/// Safety rules:
///  • Never overwrites an existing STATE.md — memory accumulates across runs, so
///    an existing file is skipped silently (and not reported as written).
///  • loop.sh is marked executable (0o755).
///  • Everything else overwrites (LOOP.md and the verifier are ours to manage).
struct LoopWriter {
    let repoURL: URL
    var binary: String = "claude"

    private var fm: FileManager { .default }

    /// Write the loop's files. Returns the relative paths actually written, in
    /// order. Throws on any filesystem error.
    @discardableResult
    func write(plan: LoopPlan) throws -> [String] {
        var written: [String] = []
        for file in LoopFileGenerator.generate(for: plan) {
            let url = repoURL.appendingPathComponent(file.relativePath)

            // STATE.md is the loop's memory — never clobber one that exists.
            if file.relativePath == "STATE.md", fm.fileExists(atPath: url.path) { continue }

            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)

            var contents = file.contents
            if file.relativePath == "loop.sh", binary != "claude" {
                // Swap the placeholder binary for the user's configured one.
                contents = contents.replacingOccurrences(
                    of: LoopFileGenerator.binaryPlaceholderLine,
                    with: "BINARY=\"\(shellSafe(binary))\"")
            }
            try contents.write(to: url, atomically: true, encoding: .utf8)

            if file.relativePath == "loop.sh" {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            written.append(file.relativePath)
        }
        return written
    }

    /// A binary path safe inside double quotes in loop.sh.
    private func shellSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "")
    }
}
