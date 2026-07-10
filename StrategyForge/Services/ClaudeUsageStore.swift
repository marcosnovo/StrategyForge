//
//  ClaudeUsageStore.swift
//  StrategyForge
//
//  Reads Claude Code's local session logs (~/.claude/projects/**/*.jsonl) and
//  aggregates real token usage into a 5-hour "block" and a rolling 7-day window,
//  per model — ClaudeKarma-style. Requires the app sandbox to be off (it is), so
//  we can read the user's home directory. Undocumented format, so parsing is
//  tolerant: unknown/legacy lines are skipped, never fatal.
//

import Foundation

/// Per-model token totals for a window.
struct ModelUsage: Equatable, Identifiable {
    var model: String        // friendly display name (e.g. "Opus 4.7")
    var tokens: Int
    var id: String { model }
}

/// Aggregated Claude usage read from local logs.
struct UsageSummary: Equatable {
    /// Start of the current 5-hour rate-limit block (hour-aligned), if any.
    var blockStart: Date?
    /// When that block resets (blockStart + 5h).
    var blockResetAt: Date?
    /// Tokens used within the current block.
    var blockTokens: Int
    /// Tokens in the trailing 7 days, and the per-model split.
    var weekTokens: Int
    var weekByModel: [ModelUsage]
    /// Most recent logged activity.
    var lastActivity: Date?
    /// When this summary was computed.
    var computedAt: Date

    var hasData: Bool { lastActivity != nil }

    static let empty = UsageSummary(blockStart: nil, blockResetAt: nil, blockTokens: 0,
                                    weekTokens: 0, weekByModel: [], lastActivity: nil,
                                    computedAt: .distantPast)
}

enum ClaudeUsageStore {

    /// The 5-hour rate-limit block length.
    private static let blockLength: TimeInterval = 5 * 3600

    /// One usage sample pulled from a log line.
    private struct Sample { let date: Date; let model: String; let tokens: Int }

    // Minimal, tolerant line shape — we only read what we aggregate.
    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let message: Message?
        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    /// Scan the local logs and aggregate. Runs synchronously — call off the main
    /// thread (via Task.detached). `now` is injectable for testing.
    static func load(now: Date = Date()) -> UsageSummary {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return .empty }

        // Only files touched in the last 8 days can hold entries for the 7-day
        // window (plus a margin for the current block), so we skip the rest.
        let cutoff = now.addingTimeInterval(-8 * 86_400)
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String) -> Date? {
            iso.date(from: s) ?? isoNoFrac.date(from: s)
        }

        var samples: [Sample] = []

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return .empty
        }
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let rv = try? url.resourceValues(forKeys: Set(keys))
            if let mod = rv?.contentModificationDate, mod < cutoff { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            text.enumerateLines { line, _ in
                // Cheap pre-filter before JSON work.
                guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return }
                guard let data = line.data(using: .utf8),
                      let parsed = try? decoder.decode(Line.self, from: data),
                      parsed.type == "assistant",
                      let ts = parsed.timestamp, let date = parseDate(ts),
                      let usage = parsed.message?.usage else { return }
                let tokens = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                    + (usage.cache_creation_input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0)
                guard tokens > 0 else { return }
                samples.append(Sample(date: date,
                                      model: friendlyModel(parsed.message?.model ?? "—"),
                                      tokens: tokens))
            }
        }

        guard !samples.isEmpty else { return .empty }
        samples.sort { $0.date < $1.date }

        // Current 5-hour block: walk forward, restarting the block whenever an entry
        // lands past the running block's reset. The final anchor is the live block.
        var anchor = floorToHour(samples[0].date)
        var blockTokens = 0
        for s in samples {
            if s.date >= anchor.addingTimeInterval(blockLength) {
                anchor = floorToHour(s.date)
                blockTokens = 0
            }
            blockTokens += s.tokens
        }
        let resetAt = anchor.addingTimeInterval(blockLength)
        // If the block already elapsed (no recent activity), report zero for the live block.
        let liveBlockTokens = now < resetAt ? blockTokens : 0
        let liveBlockStart: Date? = now < resetAt ? anchor : nil
        let liveResetAt: Date? = now < resetAt ? resetAt : nil

        // Rolling 7-day window, per model.
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        var byModel: [String: Int] = [:]
        var weekTokens = 0
        for s in samples where s.date >= weekStart {
            byModel[s.model, default: 0] += s.tokens
            weekTokens += s.tokens
        }
        let models = byModel.map { ModelUsage(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        return UsageSummary(
            blockStart: liveBlockStart,
            blockResetAt: liveResetAt,
            blockTokens: liveBlockTokens,
            weekTokens: weekTokens,
            weekByModel: models,
            lastActivity: samples.last?.date,
            computedAt: now)
    }

    private static func floorToHour(_ date: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }

    /// Map a raw model id ("claude-opus-4-7") to a short friendly name ("Opus 4.7").
    static func friendlyModel(_ raw: String) -> String {
        let r = raw.lowercased()
        func version(_ family: String) -> String {
            // Pull the trailing "-4-7" / "-4-5" → "4.7".
            let digits = raw.split(separator: "-").compactMap { Int($0) }
            let v = digits.suffix(2).map(String.init).joined(separator: ".")
            return v.isEmpty ? family : "\(family) \(v)"
        }
        if r.contains("opus") { return version("Opus") }
        if r.contains("sonnet") { return version("Sonnet") }
        if r.contains("haiku") { return version("Haiku") }
        if r.contains("fable") { return version("Fable") }
        if r == "—" || r.isEmpty { return "—" }
        return raw
    }
}
