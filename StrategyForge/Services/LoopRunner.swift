//
//  LoopRunner.swift
//  StrategyForge
//
//  Executes a loop plan locally: each iteration runs one Claude Code work turn
//  (via ClaudeRunner) and then judges the repo state with an INDEPENDENT one-shot
//  verifier (via CLIOneShotRunner) — repeating until the verifier says PASS or
//  the plan runs out of turns. Exposes observable state that drives the shared
//  loop-progress visual (LoopProgressView / LoopRunPanel).
//

import Foundation
import Observation

/// Where a running loop currently is, for the shared progress visual.
enum LoopStage: Hashable { case idle, act, verify, done, failed }

@Observable
@MainActor
final class LoopRunController {

    var isRunning = false {
        didSet { if isRunning != oldValue { onRunningChanged?(isRunning) } }
    }
    /// Notifies the owner (LoopStore) when a run starts/ends — drives the global
    /// running indicators.
    @ObservationIgnored var onRunningChanged: ((Bool) -> Void)?
    /// Called once per finished run (PASS, FAIL, error, out of turns, or
    /// done-unverified) with the run's summary. NOT called on stop()/cancel.
    @ObservationIgnored var onFinished: ((LoopRunSummary) -> Void)?
    /// 1-based current iteration; 0 when idle.
    var iteration = 0
    var maxTurns = 1
    var stage: LoopStage = .idle
    /// One entry per completed (verified) iteration: true = PASS, false = FAIL.
    var verdicts: [Bool] = []
    /// Non-destructive git snapshots taken after each iteration's work, so a run can
    /// be rewound to any point (see LoopRunPanel). Live for the current/last run.
    var checkpoints: [LoopCheckpoint] = []
    /// The verifier's one-line reason for the last verdict (or the run's error).
    var lastVerdictReason: String?
    /// Localization key for the one-line status shown under the dots.
    var statusKey = "progress.status.working"
    /// Last tool/file/command touched — raw text from the stream, not localized.
    var liveDetail = ""
    var totalTokens = 0
    var totalCostUSD = 0.0
    var startedAt: Date?
    /// true = verified PASS, false = failed/out of turns, nil = idle or unverified.
    var finishedSuccessfully: Bool?

    @ObservationIgnored private var runTask: Task<Void, Never>?

    /// Worktree isolation context for the current run (nil when running directly in the
    /// repo). Set at start when `plan.useWorktree` is on; cleared by `finalizeWorktree`.
    @ObservationIgnored private var wtBase: String?
    @ObservationIgnored private var wtDir: String?
    @ObservationIgnored private var wtBranch: String?

    deinit {
        // If the panel is torn down mid-run, stop the subprocess/stream.
        runTask?.cancel()
    }

    /// The outcome of one streamed work turn.
    private enum TurnOutcome { case finished, failed(String), sessionMissing }

    /// Build + emit the run summary for a terminal state (never for stop/cancel).
    private func emitFinished(pass: Bool?) {
        onFinished?(LoopRunSummary(date: Date(),
                                   pass: pass,
                                   reason: lastVerdictReason,
                                   iterations: iteration,
                                   tokens: totalTokens,
                                   costUSD: totalCostUSD))
    }

    /// Close out a run: settle the worktree (merge on PASS, keep the branch otherwise),
    /// then emit the summary. Used at every terminal return so isolation is honored no
    /// matter which exit the run took. No-op on the worktree side when running directly.
    private func finalizeAndEmit(pass: Bool?) async {
        await finalizeWorktree(pass: pass)
        emitFinished(pass: pass)
    }

    /// Set up a git worktree for the run and return its path (the new working dir), or
    /// nil if isolation wasn't requested. Throws a readable message if git can't create
    /// it, so the caller aborts rather than silently running in the repo unisolated.
    private func setUpWorktree(base: String, plan: LoopPlan) async throws -> String? {
        guard plan.useWorktree else { return nil }
        let slug = LoopFileGenerator.branchSlugForRun(plan.name)
        let stamp = Int(Date().timeIntervalSince1970)
        let branch = "loop/\(slug)-\(stamp)"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coral-loops-\(UUID().uuidString.prefix(8))").path
        let add = await CodeGit.addWorktree(repo: base, path: dir, branch: branch)
        guard add.ok else {
            throw NSError(domain: "Coral.Loop", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Couldn't create a git worktree: \(add.out.prefix(160))"])
        }
        // The loop's own scaffolding may be uncommitted, so a fresh checkout wouldn't
        // have it — copy LOOP.md / STATE.md / the verifier into the isolated tree.
        for rel in ["LOOP.md", "STATE.md", ".claude/agents/loop-verifier.md"] {
            let src = (base as NSString).appendingPathComponent(rel)
            let dst = (dir as NSString).appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: src) else { continue }
            try? FileManager.default.createDirectory(
                atPath: (dst as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: dst)
            try? FileManager.default.copyItem(atPath: src, toPath: dst)
        }
        wtBase = base; wtDir = dir; wtBranch = branch
        return dir
    }

    /// Settle the worktree at the end of a run. Commits whatever the run produced so
    /// nothing is lost, then — ONLY on a verified PASS — merges the branch back into the
    /// base and removes the worktree. On conflict it aborts the merge and keeps the
    /// branch; on any non-PASS outcome it keeps the branch for review and removes just
    /// the temporary worktree. Silently merging unverified work never happens.
    private func finalizeWorktree(pass: Bool?) async {
        guard let base = wtBase, let dir = wtDir, let branch = wtBranch else { return }
        wtBase = nil; wtDir = nil; wtBranch = nil
        _ = await CodeGit.commitAll(dir: dir, message: "Coral loop \(branch)")
        if pass == true {
            let merge = await CodeGit.mergeNoFF(repo: base, branch: branch,
                                                message: "Merge loop \(branch) (verified PASS)")
            if merge.ok {
                await CodeGit.removeWorktree(repo: base, path: dir)
                await CodeGit.deleteBranch(repo: base, name: branch)
            } else {
                await CodeGit.abortMerge(repo: base)
                lastVerdictReason = "PASS, but the merge hit conflicts — resolve branch \(branch) by hand."
            }
        } else {
            // Keep the branch (it holds the run's committed work) for review; drop only
            // the temporary worktree checkout.
            await CodeGit.removeWorktree(repo: base, path: dir)
        }
    }

    func start(plan: LoopPlan, repoURL: URL, binary: String) {
        guard !isRunning else { return }
        isRunning = true
        iteration = 0
        stage = .act
        verdicts = []
        checkpoints = []
        lastVerdictReason = nil
        statusKey = "progress.status.working"
        liveDetail = ""
        totalTokens = 0
        totalCostUSD = 0
        startedAt = Date()
        finishedSuccessfully = nil
        // Only goal-based loops auto-iterate: other kinds (and loops without a
        // verifier, which have no PASS/FAIL signal to iterate on) run one pass.
        maxTurns = (plan.kind == .goalBased && plan.verifierEnabled) ? max(1, plan.maxTurns) : 1

        runTask = Task { [plan, repoURL, binary] in
            defer { isRunning = false }
            // Resolving the binary spawns a login shell — keep it off the main actor.
            let resolved = await Task.detached { ClaudeRunner.resolveBinary(binary) }.value ?? binary
            // One session for the whole run so context carries across iterations
            // (mirrors ChatViewModel's per-chat sessions).
            let sessionID = UUID().uuidString.lowercased()
            var hasSession = false
            let turns = maxTurns

            // Where the work happens: the repo directly, or an isolated git worktree
            // (opt-in). If isolation was requested but git couldn't set it up, fail the
            // run rather than silently running unisolated in the repo.
            let base = repoURL.path
            let workDir: String
            do {
                workDir = try await setUpWorktree(base: base, plan: plan) ?? base
            } catch {
                stage = .failed
                statusKey = "progress.status.error"
                lastVerdictReason = String(error.localizedDescription.prefix(200))
                finishedSuccessfully = false
                emitFinished(pass: false)
                return
            }

            for turn in 1...turns {
                if Task.isCancelled { break }
                iteration = turn
                stage = .act
                statusKey = "progress.status.working"

                let prompt = Self.workPrompt(plan: plan)
                let effort = plan.effort.cliValue
                var outcome = await runWorkTurn(binary: resolved, repo: workDir,
                                                prompt: prompt, model: plan.workerModel.rawValue,
                                                sessionID: sessionID, resume: hasSession, effort: effort)
                // The CLI lost the session (e.g. cleaned ~/.claude) → retry fresh
                // once, invisibly (same resilience as ChatViewModel.send()).
                if case .sessionMissing = outcome, hasSession {
                    outcome = await runWorkTurn(binary: resolved, repo: workDir,
                                                prompt: prompt, model: plan.workerModel.rawValue,
                                                sessionID: sessionID, resume: false, effort: effort)
                }
                hasSession = true
                if case .failed(let message) = outcome {
                    if Task.isCancelled { break }
                    stage = .failed
                    statusKey = "progress.status.error"
                    lastVerdictReason = String(message.prefix(200))
                    finishedSuccessfully = false
                    await finalizeAndEmit(pass: false)
                    return
                }
                if Task.isCancelled { break }

                // Non-destructive checkpoint of the repo after this iteration's work,
                // so the run can be rewound here later (git stash-create SHA).
                if let sha = await CodeGit.snapshot(repo: workDir) {
                    checkpoints.append(LoopCheckpoint(iteration: turn, sha: sha,
                                                      reason: nil, at: Date()))
                }

                // Spend cap (opt-in): the same second abort the generated loop.sh
                // enforces, honored here too. totalCostUSD already covers every
                // turn's work + verify so far, so this bounds the whole run — not
                // just one call.
                if let cap = plan.budgetUSD, totalCostUSD > cap {
                    stage = .failed
                    statusKey = "progress.status.overBudget"
                    lastVerdictReason = String(format: "Stopped: $%.2f spent, over the $%.2f cap.",
                                               totalCostUSD, cap)
                    finishedSuccessfully = false
                    await finalizeAndEmit(pass: false)
                    return
                }

                guard plan.verifierEnabled else {
                    // Deliberate choice: with no independent verifier there is no
                    // trustworthy PASS/FAIL signal to iterate on, so we run exactly
                    // ONE act iteration and report "done, unverified" instead of
                    // pretending the goal was met (finishedSuccessfully stays nil).
                    stage = .done
                    statusKey = "progress.status.doneUnverified"
                    await finalizeAndEmit(pass: nil)
                    return
                }

                stage = .verify
                statusKey = "progress.status.verifying"
                do {
                    let runner = CLIOneShotRunner(binaries: [.claude: resolved])
                    let result = try await runner.run(prompt: Self.verifierPrompt(plan: plan),
                                                      provider: .claude,
                                                      model: plan.verifierModel.rawValue,
                                                      cwd: workDir)
                    totalTokens += result.tokens
                    totalCostUSD += result.costUSD
                    let verdict = Self.parseVerdict(result.text)
                    verdicts.append(verdict.pass)
                    lastVerdictReason = verdict.reason
                    if verdict.pass {
                        stage = .done
                        statusKey = "progress.status.pass"
                        finishedSuccessfully = true
                        await finalizeAndEmit(pass: true)
                        return
                    } else if turn < turns {
                        statusKey = "progress.status.retry"
                    } else {
                        stage = .failed
                        statusKey = "progress.status.outOfTurns"
                        finishedSuccessfully = false
                        await finalizeAndEmit(pass: false)
                    }
                } catch {
                    if Task.isCancelled { break }
                    stage = .failed
                    statusKey = "progress.status.error"
                    lastVerdictReason = String(error.localizedDescription.prefix(200))
                    finishedSuccessfully = false
                    await finalizeAndEmit(pass: false)
                    return
                }
            }
            // Settle the worktree even when the run was cancelled mid-flight (stop()):
            // no terminal `finalizeAndEmit` ran on that path, so without this the temp
            // worktree + branch would leak. No-op on every other path (wt* already
            // cleared by the finalize that emitted). pass:nil → never merges, keeps the
            // branch for review, removes just the temporary checkout.
            await finalizeWorktree(pass: nil)
            // Cancelled mid-run (stop()) → back to idle; done/failed states stick.
            if stage != .done && stage != .failed { stage = .idle }
        }
    }

    /// Stop the run. Cancelling the task ends the `for await` over the runner's
    /// AsyncStream, whose onTermination terminates the `claude` subprocess (the
    /// same mechanism ChatViewModel.stop() relies on).
    func stop() {
        runTask?.cancel()
        runTask = nil
        if stage != .done && stage != .failed { stage = .idle }
        isRunning = false
    }

    // MARK: - One work turn

    /// Stream one Claude Code work turn, updating live detail and usage totals.
    private func runWorkTurn(binary: String, repo: String, prompt: String, model: String,
                             sessionID: String, resume: Bool, effort: String) async -> TurnOutcome {
        var outcome: TurnOutcome = .finished
        for await event in ClaudeRunner.stream(binary: binary, repoPath: repo,
                                               prompt: prompt, model: model,
                                               sessionID: sessionID, resume: resume,
                                               permissionMode: "acceptEdits", extraDirs: [],
                                               effort: effort) {
            switch event {
            case .tool(let name, let detail):
                liveDetail = detail.map { "\(name) · \($0)" } ?? name
            case .fileEdited(let path):
                liveDetail = (path as NSString).lastPathComponent
            case .commandStarted(_, let command):
                liveDetail = command.count > 80 ? String(command.prefix(80)) + "…" : command
            case .usage(let tokens, let cost):
                totalTokens += tokens
                totalCostUSD += cost
            case .failed(let message):
                if resume, message.localizedCaseInsensitiveContains("No conversation found") {
                    outcome = .sessionMissing   // caller retries fresh, invisibly
                } else {
                    outcome = .failed(message)
                }
            case .finished:
                break
            default:
                break   // text/todos/delegations don't drive the loop visual
            }
        }
        return outcome
    }

    // MARK: - Prompts

    /// The compact per-iteration work prompt. Prompts are for the model, so they
    /// stay in English (UI copy is localized separately).
    static func workPrompt(plan: LoopPlan) -> String {
        var lines = [
            "You are one iteration of an autonomous work loop on this repo.",
            "Read LOOP.md in the repo root for the loop's charter.",
        ]
        if plan.memoryEnabled {
            lines.append("Also read STATE.md — memory left by previous iterations.")
        }
        lines.append("Goal ('## Done when'): \(plan.goal)")
        lines.append("Do the single next most useful step toward that goal, then stop.")
        let neverTouch = plan.neverTouch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !neverTouch.isEmpty {
            lines.append("Never touch: \(neverTouch)")
        }
        if plan.memoryEnabled {
            lines.append("Before finishing, update STATE.md with what you did and what remains.")
        }
        lines.append("Keep the step small and verifiable.")
        return lines.joined(separator: "\n")
    }

    /// The independent verifier's prompt: judge the repo state only, first line
    /// is a machine-parseable verdict.
    static func verifierPrompt(plan: LoopPlan) -> String {
        """
        You are an independent verifier. You did NOT do the work you are judging.
        Read LOOP.md in the repo root, then inspect the current repo state.
        Judge the repo state ONLY against this '## Done when' goal: \(plan.goal)
        Reply with the first line exactly `VERDICT: PASS` or `VERDICT: FAIL`,
        followed by a one-line reason.
        """
    }

    // MARK: - Verdict parsing

    /// Find the first line containing "VERDICT:" (case-insensitive, tolerant of
    /// whitespace/markdown) and read PASS/FAIL from it. Unparseable → FAIL.
    static func parseVerdict(_ text: String) -> (pass: Bool, reason: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let idx = lines.firstIndex(where: { $0.range(of: "VERDICT:", options: .caseInsensitive) != nil }) else {
            return (false, "unparseable verdict")
        }
        let line = lines[idx]
        let after = line[line.range(of: "VERDICT:", options: .caseInsensitive)!.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t*`_#"))
        let pass: Bool
        if after.range(of: "PASS", options: .caseInsensitive) != nil { pass = true }
        else if after.range(of: "FAIL", options: .caseInsensitive) != nil { pass = false }
        else { return (false, "unparseable verdict") }
        // The reason is the rest of the reply (or the remainder of the verdict line).
        var reason = lines[(idx + 1)...].joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty {
            let word = pass ? "PASS" : "FAIL"
            if let r = after.range(of: word, options: .caseInsensitive) {
                reason = after[r.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t-—:.,*`"))
            }
        }
        return (pass, String(reason.prefix(200)))
    }
}
