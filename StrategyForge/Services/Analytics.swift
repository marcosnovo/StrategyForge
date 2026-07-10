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

    /// The events we care about for the H1/H2 funnels.
    enum Event {
        case appLaunched
        case runStarted(provider: String, agents: Int, meta: Bool)
        case runFinished(provider: String, agents: Int, tokens: Int, costCents: Int, meta: Bool)
        case runCancelled
        case strategyShared(kind: String)      // "file" | "text"
        case strategyImported(kind: String)    // "file" | "text" | "repo"
        case teamCreated(fromStrategy: String)
        case missionReportExported(kind: String)  // "markdown" | "image"

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
            }
        }

        var props: [String: String] {
            switch self {
            case .appLaunched, .runCancelled:
                return [:]
            case .runStarted(let p, let a, let m):
                return ["provider": p, "agents": "\(a)", "meta": "\(m)"]
            case .runFinished(let p, let a, let t, let c, let m):
                return ["provider": p, "agents": "\(a)", "tokens": "\(t)", "cost_cents": "\(c)", "meta": "\(m)"]
            case .strategyShared(let k), .strategyImported(let k), .missionReportExported(let k):
                return ["kind": k]
            case .teamCreated(let s):
                return ["from_strategy": s]
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
