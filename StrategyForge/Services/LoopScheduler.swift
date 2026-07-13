//
//  LoopScheduler.swift
//  StrategyForge
//
//  Schedules a loop to run on a cadence via a user LaunchAgent (~/Library/
//  LaunchAgents), so it keeps firing after Coral is closed. Coral is non-sandboxed,
//  so the launchd job — which runs as the user — can reach the repo directly; there
//  is no security-scoped bookmark to carry into the launchd context. The caller
//  resolves the bookmark to a live path (that IS the validation) and we verify it
//  still exists before writing the job. The plist existence is the source of truth
//  for "is this loop scheduled".
//
//  Only loops whose launch is `./loop.sh` (turn / time / proactive) are schedulable;
//  goal loops launch interactively and aren't a fit for unattended cadence.
//

import Foundation

enum LoopScheduler {

    static func label(for id: UUID) -> String { "com.coral.loop.\(id.uuidString.lowercased())" }

    static func plistURL(for id: UUID) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label(for: id)).plist")
    }

    static func isScheduled(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(for: id).path)
    }

    /// Loops that launch via `./loop.sh` can run unattended on a schedule.
    static func canSchedule(_ plan: LoopPlan) -> Bool { plan.kind != .goalBased }

    /// Validate the repo, (re)write the loop's files so `loop.sh` exists, write the
    /// LaunchAgent plist, and load it. Returns nil on success or a message on failure.
    @discardableResult
    static func enable(plan: LoopPlan, repoURL: URL, binary: String, intervalMinutes: Int) -> String? {
        guard canSchedule(plan) else { return "This loop kind can't run on a schedule." }
        // Bookmark validation: the caller resolved the bookmark → repoURL; confirm the
        // folder still exists (moved/deleted repos must not silently schedule nothing).
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repoURL.path, isDirectory: &isDir), isDir.boolValue else {
            return "The loop's folder is missing — pick it again before scheduling."
        }
        // Make sure loop.sh (and the charter files) are present and current.
        do {
            _ = try LoopWriter(repoURL: repoURL, binary: binary).write(plan: plan)
        } catch {
            return "Couldn't write the loop files: \(error.localizedDescription)"
        }

        let label = label(for: plan.id)
        let interval = max(60, intervalMinutes * 60)
        // A login shell so the CLI (installed under ~/.npm-global etc.) is on PATH.
        let command = "cd \(shellQuote(repoURL.path)) && ./loop.sh"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/zsh", "-lc", command],
            "StartInterval": interval,
            "WorkingDirectory": repoURL.path,
            "RunAtLoad": false,
            "ProcessType": "Background",
            "StandardOutPath": "/tmp/\(label).out",
            "StandardErrorPath": "/tmp/\(label).err",
        ]
        let url = plistURL(for: plan.id)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url)
        } catch {
            return "Couldn't write the schedule: \(error.localizedDescription)"
        }

        // Load into the user's GUI domain (modern launchctl), clearing any stale copy.
        let domain = "gui/\(getuid())"
        _ = launchctl(["bootout", "\(domain)/\(label)"])
        let r = launchctl(["bootstrap", domain, url.path])
        if !r.ok {
            // Older macOS fallback.
            let legacy = launchctl(["load", "-w", url.path])
            if !legacy.ok {
                try? FileManager.default.removeItem(at: url)
                return "launchd rejected the schedule: \(r.out.isEmpty ? legacy.out : r.out)"
            }
        }
        return nil
    }

    /// Unload + remove the LaunchAgent for this loop.
    static func disable(_ id: UUID) {
        let label = label(for: id)
        let url = plistURL(for: id)
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        _ = launchctl(["unload", "-w", url.path])
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private static func launchctl(_ args: [String]) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (false, "launchctl failed to launch") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
