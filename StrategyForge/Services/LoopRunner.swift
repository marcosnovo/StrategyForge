//
//  LoopRunner.swift
//  StrategyForge
//
//  Executes a loop plan locally: each iteration runs one Claude Code work turn
//  (via ClaudeRunner), then the plan's MECHANICAL verify command (its exit code
//  is the verdict — non-zero is FAIL outright, no judge), and only then judges
//  the repo state with an INDEPENDENT one-shot verifier (via CLIOneShotRunner) —
//  repeating until the verifier says PASS or the plan runs out of turns. Exposes
//  observable state that drives the shared loop-progress visual
//  (LoopProgressView / LoopRunPanel).
//

import Foundation
import Observation

/// Where a running loop currently is, for the shared progress visual.
enum LoopStage: Hashable { case idle, act, verify, done, failed }

/// One iteration's verified result, for the per-iteration list in the run panel.
struct IterationOutcome: Identifiable, Hashable {
    let id = UUID()
    let iteration: Int
    let pass: Bool
    let reason: String
}

/// Holds the mechanical gate's spawned process so a task cancellation or the
/// timeout can terminate it safely from any thread. Mirrors CLIOneShotRunner's
/// ProcessBox: terminate() on a never-launched Process raises
/// NSInvalidArgumentException, so `adopt` refuses after cancellation.
private final class GateProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    /// Returns false when already cancelled — the caller must NOT launch then.
    func adopt(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        process = p; return true
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let p = process, p.isRunning { p.terminate() }
    }
}

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
    /// Per-iteration verdict + the verifier's one-line reason, so the panel can show
    /// "iteration 1 · FAIL · the keeper check still errors" instead of only the last one.
    var iterationOutcomes: [IterationOutcome] = []
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
    /// Monotonic run id, bumped in start() and stop(). A run's task guards every state
    /// mutation after an await on `epoch == runEpoch`, so a stopped run's still-draining
    /// task can never clobber the state of a newer run (mirrors ChatViewModel.runEpoch).
    @ObservationIgnored private var runEpoch = 0

    /// Worktree isolation context for one run (absent when running directly in the
    /// repo). Held as a LOCAL of that run's task — never shared instance state — so a
    /// stale task can only ever settle its OWN worktree, not one a newer run is using.
    private struct WorktreeContext { let base: String; let dir: String; let branch: String }

    deinit {
        // Belt-and-braces for the idle case only: mid-run the task holds self
        // strongly, so deinit can't fire until it ends — real teardown goes
        // through stop(), which LoopStore calls when the panel closes.
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
    private func finalizeAndEmit(_ wt: WorktreeContext?, epoch: Int, pass: Bool?) async {
        await finalizeWorktree(wt, epoch: epoch, pass: pass)
        emitFinished(pass: pass)
    }

    /// Set up a git worktree for the run and return its context (dir = the new working
    /// dir), or nil if isolation wasn't requested. Throws a readable message if git can't
    /// create it, so the caller aborts rather than silently running in the repo unisolated.
    private func setUpWorktree(base: String, plan: LoopPlan) async throws -> WorktreeContext? {
        guard plan.useWorktree else { return nil }
        // Worktrees need a git repo. A private scratch workspace (folder-less loop) isn't
        // one, so run directly there instead of failing — isolation is moot with no repo.
        guard await CodeGit.currentBranch(repo: base) != nil else { return nil }
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
        return WorktreeContext(base: base, dir: dir, branch: branch)
    }

    /// Settle the worktree at the end of a run. Commits whatever the run produced so
    /// nothing is lost, then — ONLY on a verified PASS — merges the branch back into the
    /// base and removes the worktree. On conflict it aborts the merge and keeps the
    /// branch; on any non-PASS outcome it keeps the branch for review and removes just
    /// the temporary worktree. Silently merging unverified work never happens.
    private func finalizeWorktree(_ wt: WorktreeContext?, epoch: Int, pass: Bool?) async {
        guard let wt else { return }
        _ = await CodeGit.commitAll(dir: wt.dir, message: "Coral loop \(wt.branch)")
        if pass == true {
            let merge = await CodeGit.mergeNoFF(repo: wt.base, branch: wt.branch,
                                                message: "Merge loop \(wt.branch) (verified PASS)")
            if merge.ok {
                await CodeGit.removeWorktree(repo: wt.base, path: wt.dir)
                await CodeGit.deleteBranch(repo: wt.base, name: wt.branch)
            } else {
                await CodeGit.abortMerge(repo: wt.base)
                if epoch == runEpoch {
                    lastVerdictReason = "PASS, but the merge hit conflicts — resolve branch \(wt.branch) by hand."
                }
            }
        } else {
            // Keep the branch (it holds the run's committed work) for review; drop only
            // the temporary worktree checkout.
            await CodeGit.removeWorktree(repo: wt.base, path: wt.dir)
        }
    }

    func start(plan: LoopPlan, repoURL: URL, binary: String) {
        guard !isRunning else { return }
        isRunning = true
        iteration = 0
        stage = .act
        verdicts = []
        iterationOutcomes = []
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

        runEpoch += 1
        let epoch = runEpoch
        runTask = Task { [plan, repoURL, binary, epoch] in
            defer { if epoch == runEpoch { isRunning = false } }
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
            // This run's worktree context lives HERE, as a task local, so a stale
            // task can never read (or destroy) a newer run's worktree.
            var worktree: WorktreeContext?
            let workDir: String
            do {
                worktree = try await setUpWorktree(base: base, plan: plan)
                workDir = worktree?.dir ?? base
            } catch {
                if Task.isCancelled || epoch != runEpoch { return }
                stage = .failed
                statusKey = "progress.status.error"
                lastVerdictReason = String(error.localizedDescription.prefix(200))
                finishedSuccessfully = false
                emitFinished(pass: false)
                return
            }

            for turn in 1...turns {
                if Task.isCancelled || epoch != runEpoch { break }
                iteration = turn
                stage = .act
                statusKey = "progress.status.working"

                let prompt = Self.workPrompt(plan: plan)
                let effort = plan.effort.cliValue
                var outcome = await runWorkTurn(binary: resolved, repo: workDir,
                                                prompt: prompt, model: plan.workerModel.rawValue,
                                                sessionID: sessionID, resume: hasSession, effort: effort,
                                                epoch: epoch)
                // The CLI lost the session (e.g. cleaned ~/.claude) → retry fresh
                // once, invisibly (same resilience as ChatViewModel.send()).
                if case .sessionMissing = outcome, hasSession {
                    outcome = await runWorkTurn(binary: resolved, repo: workDir,
                                                prompt: prompt, model: plan.workerModel.rawValue,
                                                sessionID: sessionID, resume: false, effort: effort,
                                                epoch: epoch)
                }
                hasSession = true
                if case .failed(let message) = outcome {
                    if Task.isCancelled || epoch != runEpoch { break }
                    stage = .failed
                    statusKey = "progress.status.error"
                    lastVerdictReason = String(message.prefix(200))
                    finishedSuccessfully = false
                    await finalizeAndEmit(worktree, epoch: epoch, pass: false)
                    return
                }
                if Task.isCancelled || epoch != runEpoch { break }

                // Non-destructive checkpoint of the repo after this iteration's work,
                // so the run can be rewound here later (git stash-create SHA).
                let sha = await CodeGit.snapshot(repo: workDir)
                if Task.isCancelled || epoch != runEpoch { break }
                if let sha {
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
                    await finalizeAndEmit(worktree, epoch: epoch, pass: false)
                    return
                }

                // The mechanical gate (the "dumber gate", mirroring the generated
                // loop.sh): the plan's verify command runs FIRST and its EXIT CODE is
                // the verdict — a non-zero exit is FAIL outright, no judge, so the loop
                // can't declare itself done on work the tests reject. It needs no
                // opinion, so it runs even when the LLM verifier is disabled — the
                // generated loop.sh gates on it regardless of verifierEnabled too.
                let mech = Self.mechanicalCommand(plan: plan)
                if !mech.isEmpty {
                    stage = .verify
                    statusKey = "progress.status.verifying"
                    let failure = await Self.runMechanicalGate(mech, cwd: workDir)
                    if Task.isCancelled || epoch != runEpoch { break }
                    if let failure {
                        verdicts.append(false)
                        iterationOutcomes.append(IterationOutcome(iteration: turn, pass: false,
                                                                  reason: failure))
                        lastVerdictReason = failure
                        if turn < turns {
                            statusKey = "progress.status.retry"
                        } else {
                            stage = .failed
                            statusKey = "progress.status.outOfTurns"
                            finishedSuccessfully = false
                            await finalizeAndEmit(worktree, epoch: epoch, pass: false)
                            worktree = nil
                        }
                        continue
                    }
                }

                guard plan.verifierEnabled else {
                    // Deliberate choice: with no independent verifier there is no
                    // trustworthy PASS/FAIL signal to iterate on, so we run exactly
                    // ONE act iteration and report "done, unverified" instead of
                    // pretending the goal was met (finishedSuccessfully stays nil).
                    // The mechanical gate above still applies — a failing verify
                    // command FAILs the run before it can reach this point.
                    stage = .done
                    statusKey = "progress.status.doneUnverified"
                    await finalizeAndEmit(worktree, epoch: epoch, pass: nil)
                    return
                }

                stage = .verify
                statusKey = "progress.status.verifying"

                do {
                    // The judge runs READ-ONLY: it may read the repo and run tests, but
                    // never edit — otherwise it could "fix" the very code it's grading, and
                    // a bogus PASS would auto-merge unreviewed work.
                    let runner = CLIOneShotRunner(binaries: [.claude: resolved], readOnly: true)
                    let result = try await runner.run(prompt: Self.verifierPrompt(plan: plan),
                                                      provider: .claude,
                                                      model: plan.verifierModel.rawValue,
                                                      cwd: workDir)
                    if Task.isCancelled || epoch != runEpoch { break }
                    totalTokens += result.tokens
                    totalCostUSD += result.costUSD
                    let verdict = Self.parseVerdict(result.text)
                    verdicts.append(verdict.pass)
                    iterationOutcomes.append(IterationOutcome(iteration: turn, pass: verdict.pass,
                                                              reason: verdict.reason))
                    lastVerdictReason = verdict.reason
                    if verdict.pass {
                        stage = .done
                        statusKey = "progress.status.pass"
                        finishedSuccessfully = true
                        await finalizeAndEmit(worktree, epoch: epoch, pass: true)
                        return
                    } else if turn < turns {
                        statusKey = "progress.status.retry"
                    } else {
                        stage = .failed
                        statusKey = "progress.status.outOfTurns"
                        finishedSuccessfully = false
                        await finalizeAndEmit(worktree, epoch: epoch, pass: false)
                        worktree = nil
                    }
                } catch {
                    if Task.isCancelled || epoch != runEpoch { break }
                    stage = .failed
                    statusKey = "progress.status.error"
                    lastVerdictReason = String(error.localizedDescription.prefix(200))
                    finishedSuccessfully = false
                    await finalizeAndEmit(worktree, epoch: epoch, pass: false)
                    return
                }
            }
            // Settle the worktree even when the run was cancelled mid-flight (stop()):
            // no terminal `finalizeAndEmit` ran on that path, so without this the temp
            // worktree + branch would leak. No-op on every other path (`worktree` was
            // nilled after the finalize that emitted, or the finalize returned). pass:nil
            // → never merges, keeps the branch for review, removes just the temporary
            // checkout. Runs even when the epoch moved on: it settles THIS task's own
            // worktree, which no newer run can be using.
            await finalizeWorktree(worktree, epoch: epoch, pass: nil)
            // Cancelled mid-run (stop()) → back to idle; done/failed states stick.
            if epoch == runEpoch, stage != .done && stage != .failed { stage = .idle }
        }
    }

    /// Stop the run. Cancelling the task ends the `for await` over the runner's
    /// AsyncStream, whose onTermination terminates the `claude` subprocess (the
    /// same mechanism ChatViewModel.stop() relies on).
    func stop() {
        // Orphan the still-draining task first: every epoch-guarded mutation it has
        // left now misses, so it can't clobber the state of a newer run.
        runEpoch += 1
        runTask?.cancel()
        runTask = nil
        if stage != .done && stage != .failed { stage = .idle }
        isRunning = false
    }

    // MARK: - One work turn

    /// Stream one Claude Code work turn, updating live detail and usage totals.
    private func runWorkTurn(binary: String, repo: String, prompt: String, model: String,
                             sessionID: String, resume: Bool, effort: String,
                             epoch: Int) async -> TurnOutcome {
        var outcome: TurnOutcome = .finished
        for await event in ClaudeRunner.stream(binary: binary, repoPath: repo,
                                               prompt: prompt, model: model,
                                               sessionID: sessionID, resume: resume,
                                               permissionMode: "acceptEdits", extraDirs: [],
                                               effort: effort) {
            // A stopped run's stream can still be draining when a newer run starts;
            // its events must not touch the newer run's visual/usage state.
            guard epoch == runEpoch else { continue }
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
    /// is a machine-parseable verdict. When the plan sets '## Must still hold'
    /// counter-conditions, they're spelled out with the FAIL-even-if-met rule
    /// (mirroring the generated loop-verifier.md's Goodhart guardrail), so a
    /// goal reached by gaming it can't PASS in-app either.
    static func verifierPrompt(plan: LoopPlan) -> String {
        let mustHold = plan.mustHold.trimmingCharacters(in: .whitespacesAndNewlines)
        let judge = mustHold.isEmpty
            ? "Judge the repo state ONLY against this '## Done when' goal: \(plan.goal)"
            : """
              Judge the repo state against this '## Done when' goal: \(plan.goal)
              Then check these '## Must still hold' counter-conditions — if ANY is violated,
              the verdict is FAIL even when the goal looks met (a goal reached by gaming it,
              e.g. deleting tests or weakening rules, is not a PASS):
              \(mustHold)
              """
        return """
        You are an independent verifier. You did NOT do the work you are judging.
        Read LOOP.md in the repo root, then inspect the current repo state.
        \(judge)
        Reply with the first line exactly `VERDICT: PASS` or `VERDICT: FAIL`,
        followed by a one-line reason.
        """
    }

    // MARK: - Mechanical gate

    /// The plan's mechanical verify command as trimmed non-empty lines, kept verbatim
    /// one per line — the same shape LoopFileGenerator's mechVerify feeds the generated
    /// loop.sh's `bash -e` gate, so both paths run the same commands (and a `#` comment
    /// or trailing `&&` can't break either). Empty when the plan sets none.
    static func mechanicalCommand(plan: LoopPlan) -> String {
        plan.verifyCommand
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Run the gate's lines via `bash -lc` in `cwd` (a login shell, so the user's
    /// PATH — toolchains, package managers — applies, like a hand-run ./loop.sh).
    /// `set -e` is prepended AFTER the profiles load, so every line must pass —
    /// mirroring the generated script's `bash -e` heredoc. Returns nil on exit 0,
    /// else a short failure line (command + exit code + output tail) that reads like
    /// a verifier reason. Blocks a background queue, never the caller's actor; task
    /// cancellation and the timeout both terminate the child.
    nonisolated static func runMechanicalGate(_ command: String, cwd: String,
                                              timeout: TimeInterval = 1800) async -> String? {
        let box = GateProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/bin/bash")
                    p.arguments = ["-lc", "set -e\n" + command]
                    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                    let pipe = Pipe()
                    p.standardOutput = pipe
                    p.standardError = pipe
                    p.standardInput = FileHandle.nullDevice
                    guard box.adopt(p) else {
                        cont.resume(returning: "verify command cancelled"); return
                    }
                    do { try p.run() } catch {
                        cont.resume(returning: "verify command couldn't run: \(error.localizedDescription)")
                        return
                    }
                    LiveProcesses.register(p)
                    defer { LiveProcesses.deregister(p) }   // kill-all-on-quit stops tracking it
                    // Watchdog: a hung test suite shouldn't hang the loop forever.
                    let watchdog = DispatchWorkItem { box.terminate() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                    // Drain continuously and wait on EXIT, not on pipe EOF: anything
                    // the verify command spawned inherits the write end, so a surviving
                    // grandchild would hold `readDataToEndOfFile` open forever even
                    // after the watchdog killed bash (the hazard ClaudeRunner.drainPipe
                    // exists for).
                    let output = ByteBuffer()
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
                        output.append(chunk)
                    }
                    p.waitUntilExit()
                    watchdog.cancel()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    // The handler races termination — pick up the buffered tail.
                    output.append(ClaudeRunner.drainPipe(pipe.fileHandleForReading))
                    if p.terminationStatus == 0 { cont.resume(returning: nil); return }
                    let flat = command.replacingOccurrences(of: "\n", with: "; ")
                    let shown = flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
                    let out = String(data: output.contents(), encoding: .utf8) ?? ""
                    let tail = String(out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(120))
                    var reason = "verify command `\(shown)` failed (exit \(p.terminationStatus))"
                    if !tail.isEmpty { reason += " — \(tail)" }
                    cont.resume(returning: reason)
                }
            }
        } onCancel: {
            box.terminate()
        }
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
