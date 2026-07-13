//
//  Analytics.swift
//  StrategyForge
//
//  Local, opt-in telemetry for the discovery phase. Records key funnel events to a
//  JSONL file in Application Support — NOTHING is sent anywhere. It's off by default
//  and toggled in Settings; when a real backend exists this file can be shipped or
//  streamed. Logging is fire-and-forget and off the main thread.
//

import Foundation

enum Analytics {
    /// UserDefaults key backing the Settings opt-in toggle (@AppStorage).
    static let enabledKey = "sf.telemetryEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The events we care about for the activation / retention / monetization funnels.
    enum Event {
        case appLaunched
        case runStarted(provider: String, agents: Int, meta: Bool)
        case runFinished(provider: String, agents: Int, tokens: Int, costCents: Int, meta: Bool)
        case runCancelled
        case strategyShared(kind: String)      // "file" | "text"
        case strategyImported(kind: String)    // "file" | "text" | "repo"
        case teamCreated(fromStrategy: String)
        case missionReportExported(kind: String)  // "markdown" | "image"
        // Onboarding funnel
        case onboardingStarted
        case onboardingPathSelected(path: String) // "describe" | "browse" | "skip"
        case onboardingCompleted
        case onboardingSkipped
        case repoSelected(sample: Bool)
        /// The activation aha: .claude/agents + CLAUDE.md written into a repo.
        case filesGenerated(provider: String, agents: Int)
        // Monetization funnel (wired once the paywall exists; defined now so the
        // dashboard schema is stable).
        case proTeaserShown(surface: String)      // "post_run" | "test_bench" | …
        case proTeaserClicked(surface: String)
        case checkoutStarted(provider: String)    // "lemonsqueezy" | "paddle"
        case licenseActivated
        /// Pro-moat engagement: an A/B comparison of two runs.
        case testbenchComparisonRun

        var name: String {
            switch self {
            case .appLaunched: return "app_launched"
            case .runStarted: return "run_started"
            case .runFinished: return "run_finished"
            case .runCancelled: return "run_cancelled"
            case .strategyShared: return "strategy_shared"
            case .strategyImported: return "strategy_imported"
            case .teamCreated: return "team_created"
            case .missionReportExported: return "mission_report_exported"
            case .onboardingStarted: return "onboarding_started"
            case .onboardingPathSelected: return "onboarding_path_selected"
            case .onboardingCompleted: return "onboarding_completed"
            case .onboardingSkipped: return "onboarding_skipped"
            case .repoSelected: return "repo_selected"
            case .filesGenerated: return "files_generated"
            case .proTeaserShown: return "pro_teaser_shown"
            case .proTeaserClicked: return "pro_teaser_clicked"
            case .checkoutStarted: return "checkout_started"
            case .licenseActivated: return "license_activated"
            case .testbenchComparisonRun: return "testbench_comparison_run"
            }
        }

        var props: [String: String] {
            switch self {
            case .appLaunched, .runCancelled, .onboardingStarted,
                 .onboardingCompleted, .onboardingSkipped, .licenseActivated,
                 .testbenchComparisonRun:
                return [:]
            case .runStarted(let p, let a, let m):
                return ["provider": p, "agents": "\(a)", "meta": "\(m)"]
            case .runFinished(let p, let a, let t, let c, let m):
                return ["provider": p, "agents": "\(a)", "tokens": "\(t)", "cost_cents": "\(c)", "meta": "\(m)"]
            case .strategyShared(let k), .strategyImported(let k), .missionReportExported(let k):
                return ["kind": k]
            case .teamCreated(let s):
                return ["from_strategy": s]
            case .onboardingPathSelected(let path):
                return ["path": path]
            case .repoSelected(let sample):
                return ["sample": "\(sample)"]
            case .filesGenerated(let p, let a):
                return ["provider": p, "agents": "\(a)"]
            case .proTeaserShown(let s), .proTeaserClicked(let s):
                return ["surface": s]
            case .checkoutStarted(let p):
                return ["provider": p]
            }
        }
    }

    /// Record an event (no-op unless the user opted in). Fire-and-forget, off-main.
    static func log(_ event: Event, at date: Date = Date()) {
        guard isEnabled else { return }
        let line: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: date),
            "event": event.name,
            "props": event.props,
        ]
        let url = fileURL
        Task.detached(priority: .background) {
            guard let data = try? JSONSerialization.data(withJSONObject: line),
                  let text = String(data: data, encoding: .utf8) else { return }
            append(text + "\n", to: url)
        }
    }

    /// Delete the local telemetry file (offered when the user turns telemetry off).
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Storage

    private static var fileURL: URL {
        AppPaths.supportDirectory().appendingPathComponent("telemetry.jsonl")
    }

    private static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
