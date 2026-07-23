//
//  ClaudeRunnerConcurrencyTests.swift
//  StrategyForgeTests
//
//  Covers the launch-vs-cancel gate (a turn cancelled during setup must never
//  spawn an orphan `claude`) and InactivityWatchdog's thread-safe start/cancel
//  ordering — both exercised with plain system binaries, no `claude` needed.
//

import Testing
import Foundation
@testable import Coral

/// A thread-safe boolean for observing callbacks fired on arbitrary queues.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct ClaudeRunnerConcurrencyTests {

    // MARK: LaunchGate

    @Test func cancelBeforeLaunchRefusesToSpawn() throws {
        let gate = LaunchGate()
        gate.cancel()   // the consumer cancelled while setup was still running
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["5"]
        #expect(try gate.launch(p) == false)
        #expect(!p.isRunning)   // never spawned — no orphan
    }

    @Test func cancelAfterLaunchTerminatesTheProcess() throws {
        let gate = LaunchGate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        #expect(try gate.launch(p) == true)
        gate.cancel()
        p.waitUntilExit()
        #expect(p.terminationReason == .uncaughtSignal)   // SIGTERM from cancel()
    }

    @Test func launchRethrowsSpawnFailure() {
        let gate = LaunchGate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/definitely/not/a/binary")
        #expect(throws: (any Error).self) { try gate.launch(p) }
    }

    @Test func cancelIsIdempotent() throws {
        let gate = LaunchGate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        #expect(try gate.launch(p) == true)
        gate.cancel()
        gate.cancel()   // terminationHandler and onTermination can both land
        p.waitUntilExit()
        #expect(p.terminationReason == .uncaughtSignal)
    }

    // MARK: InactivityWatchdog

    @Test func watchdogFiresAfterSilence() async throws {
        let fired = Flag()
        let w = InactivityWatchdog(timeout: 0.05) { fired.set() }
        w.start()
        try await Task.sleep(for: .milliseconds(500))
        #expect(fired.isSet)
        #expect(w.didFire)
        w.cancel()
    }

    @Test func startAfterCancelNeverArmsTheTimer() async throws {
        let fired = Flag()
        let w = InactivityWatchdog(timeout: 0.05) { fired.set() }
        // A child that exits (or a consumer that cancels) before start() reaches
        // the launch step must not leave a live timer behind.
        w.cancel()
        w.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fired.isSet)
        #expect(!w.didFire)
    }

    @Test func cancelAfterStartStopsTheTimer() async throws {
        let fired = Flag()
        // Deterministic by construction: a long timeout means the armed timer
        // CANNOT fire legitimately within the short observation window, so the
        // only way `fired` could flip is the cancelled-guard breaking — a real
        // regression, never a wall-clock race. (The earlier short-timeout version
        // flaked on loaded CI: if the test thread is preempted for longer than
        // the timeout between start() and cancel(), the timer fires legitimately
        // first. This isolates the invariant instead of racing it.)
        let w = InactivityWatchdog(timeout: 30) { fired.set() }
        w.start()
        w.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!fired.isSet)
        #expect(!w.didFire)
    }

    @Test func concurrentCancelsAreSafe() async throws {
        // terminationHandler (Foundation thread) and onTermination (consumer's
        // thread) can call cancel() at the same moment — must not crash or
        // double-release the timer.
        for _ in 0..<50 {
            let w = InactivityWatchdog(timeout: 60) {}
            w.start()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { w.cancel() }
                group.addTask { w.cancel() }
            }
        }
    }
}
