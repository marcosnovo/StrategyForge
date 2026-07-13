//
//  DiagnosticsLog.swift
//  StrategyForge
//
//  A tiny rolling diagnostics log: timestamped failure/event lines written to a
//  file in Application Support so that when something goes wrong the user can
//  export it and share it. It records ONLY what the app already surfaces (failure
//  banners, run errors) plus a small environment header — nothing is sent anywhere.
//

import Foundation

enum DiagnosticsLog {
    /// The log file (lives beside the app's other data).
    static var fileURL: URL { AppPaths.supportDirectory().appendingPathComponent("diagnostics.log") }

    /// Serialize writes so records from different actors don't interleave.
    private static let queue = DispatchQueue(label: "com.marcosnovo.coral.diagnostics")
    /// Trim the file once it grows past this, keeping the most recent tail.
    private static let maxBytes = 256 * 1024

    /// Append a timestamped line. `level` is a short tag (ERROR / WARN / INFO).
    static func record(_ message: String, level: String = "ERROR") {
        let stamp = isoFormatter.string(from: Date())
        let line = "\(stamp) [\(level)] \(message.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        queue.async {
            let fm = FileManager.default
            let url = fileURL
            if !fm.fileExists(atPath: url.path) {
                try? header().write(to: url, atomically: true, encoding: .utf8)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
            trimIfNeeded(url)
        }
    }

    /// The current log contents (empty string if there's nothing yet).
    static func contents() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Wipe the log.
    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: - Internals

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    private static func header() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "# Coral diagnostics — v\(v) (\(b)) · \(os)\n"
    }

    private static func trimIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        // Keep the header + the most recent ~60% of lines.
        let lines = text.components(separatedBy: "\n")
        let keep = lines.suffix(lines.count * 6 / 10)
        let rebuilt = header() + keep.joined(separator: "\n")
        try? rebuilt.write(to: url, atomically: true, encoding: .utf8)
    }
}
