//
//  ProvenanceDiff.swift
//  StrategyForge
//
//  Annotates a unified git diff with per-line cross-provider authorship: each added (`+`)
//  line is mapped, via the hunk headers, to its new-file line number and thus to the
//  provider that wrote it (from CrossProviderEditor's line-author map). Pure parsing, so
//  it's unit-tested; the view just colors each line by its provider.
//

import Foundation

struct ProvenanceDiffLine: Equatable, Identifiable {
    enum Kind: Equatable { case fileHeader, hunkHeader, added, removed, context }
    let index: Int
    let text: String
    let kind: Kind
    /// The provider that authored this line (added lines only, when known).
    let provider: AIProvider?
    var id: Int { index }
}

enum ProvenanceDiff {

    /// Parse `diff` (git unified diff spanning one or more files) into annotated lines,
    /// tagging each `+` line with its author's provider from `lineAuthors` (keyed by
    /// repo-relative path → one author per final-file line).
    static func annotate(_ diff: String, lineAuthors: [String: [EditProvenance?]]) -> [ProvenanceDiffLine] {
        var out: [ProvenanceDiffLine] = []
        var currentFile = ""
        var newLineNo = 0            // 1-based line number in the new file
        var i = 0
        for raw in diff.components(separatedBy: "\n") {
            defer { i += 1 }
            if raw.hasPrefix("+++ ") {
                currentFile = path(fromPlusPlusPlus: raw)
                out.append(.init(index: i, text: raw, kind: .fileHeader, provider: nil))
            } else if raw.hasPrefix("diff --git") || raw.hasPrefix("--- ") || raw.hasPrefix("index ")
                        || raw.hasPrefix("new file") || raw.hasPrefix("deleted file")
                        || raw.hasPrefix("rename ") || raw.hasPrefix("similarity ") {
                out.append(.init(index: i, text: raw, kind: .fileHeader, provider: nil))
            } else if raw.hasPrefix("@@") {
                newLineNo = newStart(fromHunkHeader: raw)
                out.append(.init(index: i, text: raw, kind: .hunkHeader, provider: nil))
            } else if raw.hasPrefix("+") {
                let p = lineAuthors[currentFile].flatMap { newLineNo >= 1 && newLineNo <= $0.count ? $0[newLineNo - 1] : nil }?.provider
                out.append(.init(index: i, text: raw, kind: .added, provider: p))
                newLineNo += 1
            } else if raw.hasPrefix("-") {
                out.append(.init(index: i, text: raw, kind: .removed, provider: nil))
            } else {
                // Context line (leading space, or a blank line inside the diff body).
                out.append(.init(index: i, text: raw, kind: .context, provider: nil))
                newLineNo += 1
            }
        }
        return out
    }

    // MARK: - Parsing helpers

    /// "+++ b/Sources/Foo.swift" → "Sources/Foo.swift" (strips the a//b/ prefix).
    private static func path(fromPlusPlusPlus line: String) -> String {
        var p = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if p == "/dev/null" { return "" }
        if p.hasPrefix("b/") || p.hasPrefix("a/") { p = String(p.dropFirst(2)) }
        return p
    }

    /// "@@ -12,7 +34,9 @@ func x()" → 34 (the new-file start line).
    private static func newStart(fromHunkHeader line: String) -> Int {
        // Find the "+<num>" token between the @@ markers.
        guard let plus = line.range(of: "+") else { return 1 }
        let tail = line[plus.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits) ?? 1
    }
}
