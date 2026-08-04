//
//  DiffReviewer.swift
//  StrategyForge
//
//  Automated code review of the working diff (the in-scope idea from LangChain's
//  "software factory": OpenSWE Review). An INDEPENDENT read-only agent reads `git diff`
//  and reports bugs/regressions before you commit or open a PR — the app's "reviewer ≠
//  author" guarantee applied to code. Pure prompt/parse + an injected OneShotRunner, so
//  it's unit-tested with a mock and run for real with the CLI.
//

import Foundation

/// How serious a finding is — drives ordering, color, and the optional commit gate.
enum ReviewSeverity: String, Codable, CaseIterable, Sendable {
    case high, medium, low

    /// Sort weight (high first).
    var rank: Int { switch self { case .high: 0; case .medium: 1; case .low: 2 } }
    var labelKey: String { "review.severity.\(rawValue)" }
}

/// One issue the reviewer found in the diff.
struct ReviewFinding: Identifiable, Hashable, Sendable {
    var id = UUID()
    var severity: ReviewSeverity
    var title: String
    var detail: String
    /// Repo-relative file the issue is in (may be empty if the model didn't pin it).
    var file: String
    /// 1-based line, or nil.
    var line: Int?
}

/// The outcome of reviewing a diff.
struct DiffReview: Sendable {
    var findings: [ReviewFinding]
    /// Set when the reviewer itself failed to run (CLI missing, timeout, crash) —
    /// distinct from a clean pass, so the UI never shows "no issues found" for a
    /// review that never happened.
    var error: String? = nil
    /// A high-severity finding = something you'd want fixed before merging.
    var hasBlocking: Bool { findings.contains { $0.severity == .high } }
    var isClean: Bool { findings.isEmpty && error == nil }
}

enum DiffReviewer {

    /// The reviewer prompt: grade the diff independently, report issues as strict JSON.
    static func reviewPrompt(diff: String) -> String {
        """
        You are an INDEPENDENT code reviewer. You did not write this change; assume it may
        be broken and find where. Review the unified diff below for BUGS and REGRESSIONS —
        logic errors, off-by-one, nil/unwrap crashes, broken error handling, races,
        security issues, changes that break existing behavior, and claims not backed by the
        code. Ignore pure style. If the diff is fine, return an empty array.

        Respond with ONLY a JSON array, no prose, no code fences:
        [{"severity":"high|medium|low","title":"<short>","detail":"<what's wrong + the fix>","file":"<path>","line":<number or null>}]

        DIFF:
        \(diff)
        """
    }

    /// Turn the reviewer's findings into an instruction for the AUTHOR agent to fix them
    /// — the opt-in "close the loop" step. The reviewer stays independent (it only grades);
    /// the fix is applied by the same team that wrote the code, in its own chat turn. Pure
    /// so it's unit-tested; returns nil when there's nothing actionable to send back.
    static func fixPrompt(findings: [ReviewFinding]) -> String? {
        let actionable = findings.sorted { $0.severity.rank < $1.severity.rank }
        guard !actionable.isEmpty else { return nil }
        let items = actionable.enumerated().map { i, f -> String in
            let loc: String
            if f.file.isEmpty { loc = "" }
            else if let line = f.line { loc = " [\(f.file):\(line)]" }
            else { loc = " [\(f.file)]" }
            let detail = f.detail.isEmpty ? "" : " — \(f.detail)"
            return "\(i + 1). (\(f.severity.rawValue))\(loc) \(f.title)\(detail)"
        }.joined(separator: "\n")
        return """
        An independent code review of your working changes found the issues below. Fix each \
        one in place, then briefly note what you changed. Address the high-severity items \
        first. If any finding is a false positive, say why instead of changing the code.

        REVIEW FINDINGS:
        \(items)
        """
    }

    /// Tolerant parse: extract the first JSON array even if wrapped; drop malformed
    /// entries; clamp unknown severities to medium; sort high-severity first.
    static func parseFindings(_ text: String) -> [ReviewFinding] {
        guard let arr = ModelJSON.firstArray(in: text) else { return [] }
        let findings: [ReviewFinding] = arr.compactMap { item in
            guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let severity = ReviewSeverity(rawValue: (item["severity"] as? String)?.lowercased() ?? "") ?? .medium
            let detail = (item["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let file = (item["file"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // line may arrive as a number or a numeric string; nil/0 → no line.
            let line: Int? = (item["line"] as? Int) ?? (item["line"] as? String).flatMap { Int($0) }
            return ReviewFinding(severity: severity, title: title, detail: detail,
                                 file: file, line: (line ?? 0) > 0 ? line : nil)
        }
        return findings.sorted { $0.severity.rank < $1.severity.rank }
    }

    /// Merge findings from a PANEL of independent judges (ideally different model families):
    /// dedupe the same issue (normalized title + file), keep the highest severity anyone
    /// reported, and count how many judges agreed. Averaging across families is what breaks a
    /// single judge's correlated bias (Eval Engineering 2026). Sorted high-severity first, then
    /// most-agreed. Each inner array is one judge's findings.
    static func combinePanel(_ perJudge: [[ReviewFinding]]) -> [(finding: ReviewFinding, agree: Int)] {
        var order: [String] = []
        var map: [String: (finding: ReviewFinding, agree: Int)] = [:]
        for judge in perJudge {
            var seen = Set<String>()
            for f in judge {
                let key = String(f.title.lowercased().prefix(60)) + "\u{1}" + f.file.lowercased()
                if map[key] == nil { map[key] = (f, 0); order.append(key) }
                else if f.severity.rank < map[key]!.finding.severity.rank { map[key]!.finding.severity = f.severity }
                if !seen.contains(key) { map[key]!.agree += 1; seen.insert(key) }
            }
        }
        return order.compactMap { map[$0] }.sorted {
            $0.finding.severity.rank != $1.finding.severity.rank
                ? $0.finding.severity.rank < $1.finding.severity.rank
                : $0.agree > $1.agree
        }
    }

    /// Review a diff via the (independent, read-only) runner. An empty/whitespace diff
    /// yields a clean review; a failed run yields a review carrying `error`, so callers
    /// can't mistake "the reviewer never ran" for "no issues found".
    static func review(diff: String, runner: OneShotRunner) async -> DiffReview {
        guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DiffReview(findings: [])
        }
        do {
            let result = try await runner.run(prompt: reviewPrompt(diff: diff),
                                              provider: .claude, model: "", cwd: nil)
            return DiffReview(findings: parseFindings(result.text))
        } catch {
            let message = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
            return DiffReview(findings: [], error: message)
        }
    }
}
