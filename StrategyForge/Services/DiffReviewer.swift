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
