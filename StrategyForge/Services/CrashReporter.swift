//
//  CrashReporter.swift
//  StrategyForge
//
//  Local-only crash/hang reporting. MetricKit hands us diagnostic payloads on the
//  NEXT launch after a crash, hang, or CPU/disk exception; we summarize each one into
//  the same rolling DiagnosticsLog the user can already export. Nothing leaves the
//  device — there is no network call here, by design (see the privacy note in Settings).
//

import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

#if canImport(MetricKit)
/// Subscribes to MetricKit and records crash/hang diagnostics into `DiagnosticsLog`.
/// Kept as a retained singleton because `MXMetricManager` holds the subscriber weakly.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    /// Start receiving diagnostics. Safe to call once at launch; idempotent.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// Aggregated performance metrics — we don't record these (no analytics posture),
    /// but the protocol requires the method.
    func didReceive(_ payloads: [MXMetricPayload]) {}

    /// Crash / hang / CPU / disk diagnostics from a previous run. Summarize each into
    /// the local log so a user report includes what actually went wrong.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let meta = crash.metaData
                var parts = ["MetricKit crash"]
                if let type = crash.exceptionType { parts.append("exceptionType=\(type)") }
                if let code = crash.exceptionCode { parts.append("code=\(code)") }
                if let signal = crash.signal { parts.append("signal=\(signal)") }
                if let reason = crash.terminationReason { parts.append("reason=\(reason)") }
                parts.append("app=\(meta.applicationBuildVersion) os=\(meta.osVersion)")
                DiagnosticsLog.record(parts.joined(separator: " "), level: "CRASH")
            }
            for hang in payload.hangDiagnostics ?? [] {
                let ms = hang.hangDuration.converted(to: .milliseconds).value
                DiagnosticsLog.record("MetricKit hang \(Int(ms))ms os=\(hang.metaData.osVersion)", level: "WARN")
            }
        }
    }
}
#endif
