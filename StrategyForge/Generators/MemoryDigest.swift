//
//  MemoryDigest.swift
//  StrategyForge
//
//  Renders a set of learnings into a compact markdown block for injection into a
//  generated CLAUDE.md (see ClaudeMdGenerator.section, which appends this inside the
//  managed CORAL block and neutralizes any stray markers). Pure string builder.
//

import Foundation

enum MemoryDigest {

    /// A markdown "Learnings from past runs" block, grouped by kind. Empty input → "".
    /// The heading order is patterns → decisions → pitfalls; only non-empty groups show.
    static func render(_ learnings: [Learning]) -> String {
        guard !learnings.isEmpty else { return "" }

        var out = "## Learnings from past runs\n\n"
        out += "Durable knowledge distilled from earlier work in Coral. Apply what fits the task; don't force it.\n\n"
        if learnings.contains(where: { $0.scope == .team }) {
            out += "Entries marked `[team]` are shared team conventions — treat them as binding unless the task explicitly overrides them. The rest are personal preferences.\n\n"
        }

        for (kind, heading) in [(LearningKind.pattern, "Patterns that worked"),
                                (.decision, "Decisions & rationale"),
                                (.mistake, "Pitfalls to avoid")] {
            let group = learnings.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            out += "### \(heading)\n\n"
            for l in group {
                let title = l.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = l.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                // Mark the team level so the agent can tell a shared convention (binding)
                // from a personal preference (advisory). Personal entries stay unmarked, so
                // a base with no team learnings renders exactly as it did before.
                let level = l.scope == .team ? "[team] " : ""
                if body.isEmpty || body == title {
                    out += "- \(level)**\(title)**\n"
                } else {
                    out += "- \(level)**\(title)** — \(body)\n"
                }
            }
            out += "\n"
        }
        return out
    }
}
