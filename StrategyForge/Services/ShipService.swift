//
//  ShipService.swift
//  StrategyForge
//
//  Bet 4 — a THIN "ship it" step: don't be a PaaS, just drive the deploy CLIs the user already
//  has (Vercel / Netlify / Cloudflare `wrangler`) to publish the repo the team just built. Coral
//  detects which are installed, runs the one-shot deploy in the repo, and pulls the live URL out
//  of the output. Auth is the CLI's own (the user is logged into their provider). Publishing is
//  outward-facing, so the UI always confirms first.
//

import Foundation

enum ShipTool: String, CaseIterable, Identifiable, Sendable {
    case vercel, netlify, cloudflare
    var id: String { rawValue }
    var binary: String { self == .cloudflare ? "wrangler" : rawValue }
    var displayName: String {
        switch self { case .vercel: "Vercel"; case .netlify: "Netlify"; case .cloudflare: "Cloudflare Pages" }
    }
    /// The one-shot production-deploy argv, run with cwd = the repo.
    func args(dir: String) -> [String] {
        switch self {
        case .vercel:     return ["--yes", "--prod"]
        case .netlify:    return ["deploy", "--prod"]
        case .cloudflare: return ["pages", "deploy", dir]
        }
    }
}

struct ShipResult: Sendable { var ok: Bool; var url: String?; var log: String }

enum ShipService {
    /// Which deploy CLIs are installed right now.
    static func available() -> [ShipTool] {
        ShipTool.allCases.filter { ClaudeRunner.resolveBinary($0.binary) != nil }
    }

    /// Run `tool`'s production deploy in `repo`, returning the exit status, extracted URL, and log.
    static func deploy(_ tool: ShipTool, repo: String) async -> ShipResult {
        guard let bin = ClaudeRunner.resolveBinary(tool.binary) else {
            return ShipResult(ok: false, url: nil, log: "\(tool.displayName) CLI (\(tool.binary)) isn't installed.")
        }
        let (out, err, status) = await launch(bin: bin, args: tool.args(dir: repo), cwd: repo)
        let combined = out + "\n" + err
        return ShipResult(ok: status == 0, url: firstURL(in: combined), log: combined.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The first https URL in the deploy output — the live site.
    static func firstURL(in text: String) -> String? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let urls = d.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
            .filter { $0.hasPrefix("https://") }
        // Prefer a *.vercel.app / netlify / pages.dev deployment URL over docs links.
        return urls.first { $0.contains(".vercel.app") || $0.contains("netlify.app") || $0.contains("pages.dev") }
            ?? urls.first
    }

    private nonisolated static func launch(bin: String, args: [String], cwd: String) async -> (String, String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = args
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let binDir = (bin as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env
                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe; p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: ("", error.localizedDescription, -1)); return
                }
                LiveProcesses.register(p)
                defer { LiveProcesses.deregister(p) }
                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: watchdog)
                var errData = Data()
                let g = DispatchGroup(); g.enter()
                DispatchQueue.global(qos: .userInitiated).async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                g.wait(); p.waitUntilExit(); watchdog.cancel()
                cont.resume(returning: (String(data: outData, encoding: .utf8) ?? "",
                                        String(data: errData, encoding: .utf8) ?? "", p.terminationStatus))
            }
        }
    }
}
