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
            return "\(binary) --model \(plan.workerModel.rawValue) --effort \(plan.effort.cliValue)\n"
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

    /// Consecutive failed work turns that trip the goal loop's circuit breaker
    /// (mirrors the article's `MAX_FAILS=3` — distinct from the turn brake).
    static let maxConsecutiveFails = 3

    private static func loopSh(_ plan: LoopPlan) -> String {
        let script: String
        switch plan.kind {
        case .goalBased: script = goalScript(plan)
        case .turnBased: script = turnScript(plan)
        case .timeBased: script = timeScript(plan)
        case .proactive: script = proactiveScript(plan)
        }
        // Worktree isolation is a post-process wrap: it injects a preamble right after
        // `set -euo pipefail` and never touches each kind's internal flow, so the loop
        // logic stays exactly as tested. Off → the script is byte-identical to before.
        return plan.useWorktree ? injectWorktree(into: script, plan) : script
    }

    // MARK: - Worktree isolation (opt-in)

    /// Insert the worktree preamble right after the script's `set -euo pipefail`.
    private static func injectWorktree(into script: String, _ plan: LoopPlan) -> String {
        let anchor = "set -euo pipefail\n"
        guard let r = script.range(of: anchor) else { return script }
        var s = script
        s.replaceSubrange(r, with: anchor + "\n" + worktreePreamble(plan) + "\n")
        return s
    }

    /// A git-safe branch slug from the loop's name (letters/digits, single dashes).
    private static func branchSlug(_ plan: LoopPlan) -> String {
        branchSlugForRun(plan.name)
    }

    /// Shared slug builder, also used by the in-app runner so its branch names match
    /// the generated script's convention (`loop/<slug>-…`).
    static func branchSlugForRun(_ name: String) -> String {
        let lowered = flat(name).lowercased()
        var s = String(lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "loop" : String(s.prefix(40))
    }

    /// The bash preamble that runs the loop in its own git worktree. It carries the
    /// loop's own (possibly uncommitted) scaffolding into the fresh tree, then installs
    /// an EXIT trap that — and ONLY when the run exited 0 with a verified `VERDICT: PASS`
    /// — merges the branch back into the base and removes the worktree. Any other
    /// outcome (failure, brake, conflict, or no verifier signal) leaves the branch for
    /// review, so unverified work is never silently merged. The trap is installed AFTER
    /// the `cd`, so a failed `worktree add` can never commit the user's main tree.
    private static func worktreePreamble(_ plan: LoopPlan) -> String {
        """
        # --- Coral worktree isolation --------------------------------------------
        # Runs this loop in its own git worktree on a fresh branch, so parallel loops
        # never fight over the working tree. On a verified PASS the branch is merged
        # back into the base branch and the worktree removed; any other outcome leaves
        # it for you to review. Generated by Coral (opt-in).
        CORAL_MAIN="$(git rev-parse --show-toplevel)"
        CORAL_BASE="$(git rev-parse --abbrev-ref HEAD)"
        CORAL_BRANCH="loop/\(branchSlug(plan))-$(date +%Y%m%d-%H%M%S)-$$"
        CORAL_WT="$CORAL_MAIN/../.coral-loops/$CORAL_BRANCH"
        VERDICT=""
        git worktree add -b "$CORAL_BRANCH" "$CORAL_WT" >&2
        for f in LOOP.md STATE.md loop.sh; do
          if [ -f "$CORAL_MAIN/$f" ]; then cp "$CORAL_MAIN/$f" "$CORAL_WT/$f" || true; fi
        done
        if [ -f "$CORAL_MAIN/.claude/agents/loop-verifier.md" ]; then
          mkdir -p "$CORAL_WT/.claude/agents"
          cp "$CORAL_MAIN/.claude/agents/loop-verifier.md" "$CORAL_WT/.claude/agents/"
        fi
        cd "$CORAL_WT"
        coral_finish() {
          local code=$?
          git add -A >/dev/null 2>&1 || true
          # Don't merge the loop's own scratch artifacts (the work-turn stderr capture).
          git reset -q -- err.log >/dev/null 2>&1 || true
          git commit -m "Coral loop $CORAL_BRANCH" --quiet >/dev/null 2>&1 || true
          if [ "$code" -eq 0 ] && printf '%s' "$VERDICT" | grep -q "VERDICT: PASS"; then
            if git -C "$CORAL_MAIN" merge --no-ff "$CORAL_BRANCH" -m "Merge loop $CORAL_BRANCH (verified PASS)" >&2; then
              git -C "$CORAL_MAIN" worktree remove "$CORAL_WT" --force >/dev/null 2>&1 || true
              git -C "$CORAL_MAIN" branch -D "$CORAL_BRANCH" >/dev/null 2>&1 || true
              echo "Coral: merged $CORAL_BRANCH into $CORAL_BASE." >&2
            else
              git -C "$CORAL_MAIN" merge --abort >/dev/null 2>&1 || true
              echo "Coral: PASS but merge hit conflicts — resolve $CORAL_BRANCH by hand ($CORAL_WT)." >&2
            fi
          else
            echo "Coral: left this run on branch $CORAL_BRANCH ($CORAL_WT) for review." >&2
          fi
        }
        trap coral_finish EXIT
        # --- end Coral worktree isolation ----------------------------------------
        """
    }

    /// The verify step for the single-pass scripts (turn / time / proactive). With
    /// worktree isolation on, it captures the verdict into `$VERDICT` (a global the
    /// EXIT trap reads to gate the merge) as well as printing it; otherwise it prints
    /// the verdict directly, exactly as before.
    private static func verifyStep(_ plan: LoopPlan) -> String {
        guard plan.useWorktree else { return verifyCommand(plan, capture: false) }
        return verifyCommand(plan, capture: true) + "\necho \"$VERDICT\""
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
    /// The verify call. When `budget` is set (goal loops with a spend cap), the
    /// verifier invocation carries `--max-budget-usd` too, so a repeated-FAIL loop
    /// can't run the judge past the cap even though the judge's cost isn't summed
    /// into the work-turn tally.
    private static func verifyCommand(_ plan: LoopPlan, capture: Bool, budget: Bool = false) -> String {
        let prompt = plan.verifierEnabled
            ? "Use the loop-verifier subagent to judge this repo against '## Done when' in LOOP.md. Reply with its verdict verbatim."
            : "Judge this repo against '## Done when' in LOOP.md. Reply with exactly VERDICT: PASS or VERDICT: FAIL on the first line, then bullet reasons."
        let cap = budget ? "--max-budget-usd \"$BUDGET_USD\" " : ""
        let call = "\"$BINARY\" -p \(cap)\\\n  \"\(prompt)\""
        // Capture form: `|| true` so a transient judge failure (rate-limit, network) can't
        // trip `set -e` and kill the whole loop — an empty $VERDICT just reads as "not a
        // PASS" and the loop retries next turn.
        return capture ? "VERDICT=\"$(\(call) || true)\"" : call
    }

    private static func goalScript(_ plan: LoopPlan) -> String {
        let judgeComment = plan.verifierEnabled
            ? "# JUDGE — an independent verifier grades the work (the maker never grades itself)."
            : "# JUDGE — no independent verifier configured: the session grades itself (weaker)."
        let work = workPrompt(plan, verb: "Do the single most useful next step toward '## Done when'.")
        let hasBudget = plan.budgetUSD != nil

        var out: [String] = []
        out += [
            "#!/bin/bash",
            "#",
            "# \(displayName(plan)) — goal loop (Goal → Try → Judge → Done), generated by Coral.",
            "# Re-runs Claude until the verifier says PASS, or a hard stop is hit: the",
            "# turn limit (emergency brake), \(hasBudget ? "the spend cap, " : "")or \(maxConsecutiveFails) failed turns in a row.",
        ]
        if plan.memoryEnabled {
            out += ["# Safe to re-run: STATE.md carries memory between runs, so run N+1",
                    "# resumes instead of restarting."]
        } else {
            out += ["# Safe to re-run."]
        }
        out += [
            "#",
            "set -euo pipefail",
            "",
            "\(binaryPlaceholderLine)          # the Claude Code CLI",
            "MAX_TURNS=\(turns(plan))             # emergency brake — hard stop",
            "MAX_FAILS=\(maxConsecutiveFails)               # circuit breaker — consecutive failed turns",
            "MODEL=\"\(plan.workerModel.rawValue)\"  # the worker's model",
            "EFFORT=\"\(plan.effort.cliValue)\"          # how hard it thinks (low|medium|high|xhigh|max)",
        ]
        if let budget = plan.budgetUSD {
            out += ["BUDGET_USD=\(money(budget))            # spend cap — stop before this is exceeded"]
        }
        out += ["", "fails=0"]
        if hasBudget { out += ["spent=0"] }
        out += [""]

        if hasBudget {
            // Pull total_cost_usd out of Claude Code's JSON result. jq if present,
            // else a portable grep — no hard dependency on jq.
            out += [
                "# Read a turn's real cost from Claude Code's JSON output.",
                "extract_cost() {",
                "  if command -v jq >/dev/null 2>&1; then",
                "    jq -r '.total_cost_usd // 0' 2>/dev/null",
                "  else",
                "    grep -o '\"total_cost_usd\"[[:space:]]*:[[:space:]]*[0-9][0-9.]*' | grep -o '[0-9][0-9.]*' | tail -n1",
                "  fi",
                "}",
                "",
            ]
        }

        out += [
            "for TURN in $(seq 1 \"$MAX_TURNS\"); do",
            "  echo \"== turn $TURN of $MAX_TURNS ==\"",
            "",
            "  # TRY — one focused step toward the goal, never the whole goal at once.",
        ]
        if hasBudget {
            // Capture JSON so we can read the cost; a non-zero exit trips the breaker.
            out += [
                "  if OUT=\"$(\"$BINARY\" -p --output-format json --model \"$MODEL\" --effort \"$EFFORT\" \\",
                "      --max-budget-usd \"$BUDGET_USD\" \\",
                "      \"\(work)\" 2>err.log)\"; then",
                "    fails=0",
                "  else",
                "    fails=$((fails + 1))",
                "    echo \"Work turn failed ($fails/$MAX_FAILS):\"; tail -n 3 err.log >&2",
                "    [ \"$fails\" -ge \"$MAX_FAILS\" ] && { echo \"Circuit breaker: $MAX_FAILS turns failed in a row.\"; exit 2; }",
                "    continue",
                "  fi",
                "",
                "  # BUDGET — tally this turn's cost and stop before the cap is passed.",
                "  COST=\"$(printf '%s' \"$OUT\" | extract_cost || true)\"; COST=\"${COST:-0}\"",
                "  spent=\"$(awk -v a=\"$spent\" -v b=\"$COST\" 'BEGIN{printf \"%.4f\", a + b}')\"",
                "  echo \"  turn cost \\$$COST · total \\$$spent of \\$$BUDGET_USD\"",
                "  if awk -v s=\"$spent\" -v c=\"$BUDGET_USD\" 'BEGIN{exit !(s > c)}'; then",
                "    echo \"Budget stop: \\$$spent spent, over the \\$$BUDGET_USD cap.\"; exit 3",
                "  fi",
            ]
        } else {
            out += [
                "  if \"$BINARY\" -p --model \"$MODEL\" --effort \"$EFFORT\" \\",
                "      \"\(work)\" 2>err.log; then",
                "    fails=0",
                "  else",
                "    fails=$((fails + 1))",
                "    echo \"Work turn failed ($fails/$MAX_FAILS):\"; tail -n 3 err.log >&2",
                "    [ \"$fails\" -ge \"$MAX_FAILS\" ] && { echo \"Circuit breaker: $MAX_FAILS turns failed in a row.\"; exit 2; }",
                "    continue",
                "  fi",
            ]
        }

        out += [
            "",
            "  \(judgeComment)",
            "  \(verifyCommand(plan, capture: true, budget: hasBudget))",
            "  echo \"$VERDICT\"",
            "",
            "  # DONE — stop as soon as the work passes.",
            "  case \"$VERDICT\" in",
            "    *\"VERDICT: PASS\"*) echo \"Goal met after $TURN turn(s).\"; exit 0 ;;",
            "  esac",
            "done",
            "",
            "echo \"Emergency brake: $MAX_TURNS turns without a PASS. Read \(plan.memoryEnabled ? "STATE.md and " : "")LOOP.md and adjust.\"",
            "exit 1",
        ]
        return out.joined(separator: "\n") + "\n"
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
        EFFORT="\(plan.effort.cliValue)"          # how hard it thinks (low|medium|high|xhigh|max)

        # WORK — one round against the goal in LOOP.md.
        "$BINARY" -p --model "$MODEL" --effort "$EFFORT" \\
          "\(workPrompt(plan, verb: "Do one round of work toward '## Done when'."))"

        # CHECK — a verdict on where things stand, so your next prompt is informed.
        \(verifyStep(plan))

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
        EFFORT="\(plan.effort.cliValue)"          # how hard it thinks (low|medium|high|xhigh|max)

        mkdir -p logs   # cron redirects output here (see the line above)

        # CHECK + REACT — one scheduled pass; WAIT is cron's job.
        "$BINARY" -p --model "$MODEL" --effort "$EFFORT" \\
          "\(workPrompt(plan, verb: "Run the scheduled check described in '## Goal'; react only if something needs it."))"

        # A verdict on the pass lands in the log, so drift is caught early.
        \(verifyStep(plan))
        """
    }

    private static func proactiveScript(_ plan: LoopPlan) -> String {
        """
        #!/bin/bash
        #
        # \(displayName(plan)) — proactive loop (Event → Route → Work → Review), generated by Coral.
        # Fires on an event, with no human online. Hook it up, for example:
        #   - CI failure : run `./loop.sh "CI failed on $GITHUB_SHA"` as the failure step
        #   - Webhook    : have the receiver run `cd \(plan.repoPath.map(shSingleQuoted) ?? "<repo>") && ./loop.sh "$EVENT_SUMMARY"`
        #
        set -euo pipefail

        \(binaryPlaceholderLine)
        MODEL="\(plan.workerModel.rawValue)"
        EFFORT="\(plan.effort.cliValue)"          # how hard it thinks (low|medium|high|xhigh|max)

        EVENT="${1:-unspecified event}"   # a one-line summary of what fired

        # ROUTE + WORK — decide what the event needs, then do exactly that.
        "$BINARY" -p --model "$MODEL" --effort "$EFFORT" \\
          "\(workPrompt(plan, verb: "An event fired: $EVENT. Route it per '## Goal' and do the work it needs."))"

        # REVIEW — unattended work gets reviewed before anyone trusts it.
        \(verifyStep(plan))
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

    /// Single-quote a value for a POSIX shell (crontab lines are `sh`), so a repo path
    /// with spaces or shell metacharacters can't break — or inject into — the line.
    private static func shSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The crontab line for a time-based loop. `*/N` is only valid below an hour,
    /// so hourly-and-up cadences switch to an hour schedule.
    private static func cronLine(_ plan: LoopPlan) -> String {
        let m = max(plan.intervalMinutes, 1)
        let schedule: String
        if m < 60 { schedule = "*/\(m) * * * *" }
        else if m % 60 == 0 { schedule = "0 */\(m / 60) * * *" }
        else { schedule = "*/30 * * * *" }
        let dir = plan.repoPath.map(shSingleQuoted) ?? "<repo>"
        return "\(schedule) cd \(dir) && ./loop.sh >> logs/loop.log 2>&1"
    }

    /// A dollar amount for a shell literal: whole numbers drop the decimals (5),
    /// fractions keep the minimum digits (2.5, 0.5). Always non-negative (clamped
    /// on the model side).
    private static func money(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
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
