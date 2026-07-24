//
//  StateFileParser.swift
//  StrategyForge
//
//  Turns an existing loop STATE.md into cross-project learnings — the bridge from
//  per-loop memory (which lives in one repo) into the global knowledge base. Pure text
//  parsing; the STATE.md format is the fixed set of `##` headings written by
//  LoopFileGenerator.stateMd. Guidance HTML comments and empty sections yield nothing.
//

import Foundation

enum StateFileParser {

    /// Map a STATE.md section heading (normalized) to a learning kind, or nil to skip.
    private static func kind(forHeading heading: String) -> LearningKind? {
        let h = heading.lowercased().trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("general rules") { return .pattern }
        if h.hasPrefix("verified facts") { return .decision }
        if h.hasPrefix("lessons learned") { return .mistake }
        if h.hasPrefix("open failures") { return .mistake }
        return nil   // "Last session" (narrative) and anything unknown are skipped
    }

    /// Extract learnings from a STATE.md's text, tagged + scoped to `repo`.
    static func learnings(fromStateMd text: String, repo: String) -> [Learning] {
        let repoName = (repo as NSString).lastPathComponent.lowercased()
        var result: [Learning] = []
        var currentKind: LearningKind?
        var buffer: [String] = []   // accumulated non-comment content lines of a section

        func flushSection() {
            guard let kind = currentKind else { buffer = []; return }
            for item in items(from: buffer) {
                let title = String(item.prefix(80)).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                let body = item.count > 80 ? item : ""
                result.append(Learning(
                    kind: kind, title: title, body: body,
                    tags: repoName.isEmpty ? [] : [repoName],
                    repoScope: repo.isEmpty ? nil : repo,
                    source: LearningSource(origin: .stateFile, detail: repo)))
            }
            buffer = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flushSection()
                currentKind = kind(forHeading: String(line.dropFirst(3)))
            } else if line.hasPrefix("# ") {
                flushSection(); currentKind = nil          // document title — reset
            } else if line.hasPrefix("<!--") {
                continue                                    // guidance comment — skip
            } else {
                buffer.append(line)
            }
        }
        flushSection()
        return result
    }

    /// Split a section's content lines into distinct items: each bullet is its own item;
    /// runs of plain prose lines collapse into one item.
    private static func items(from lines: [String]) -> [String] {
        var items: [String] = []
        var prose: [String] = []
        func flushProse() {
            let joined = prose.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { items.append(joined) }
            prose = []
        }
        for line in lines {
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushProse()
                let t = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { items.append(t) }
            } else if line.isEmpty {
                flushProse()
            } else {
                prose.append(line)
            }
        }
        flushProse()
        return items
    }
}
