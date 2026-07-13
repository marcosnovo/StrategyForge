//
//  FileDiff.swift
//  StrategyForge
//
//  A pre-write diff: what a generated file would change on disk, computed as pure
//  data so the UI can show the developer exactly what will happen BEFORE anything
//  is written. Mirrors the "generators are pure, StrategyWriter does I/O" split —
//  the diff itself never touches disk; callers pass in the existing contents.
//

import Foundation

/// One line of a computed diff.
struct FileDiffLine: Equatable, Hashable {
    enum Kind: Equatable { case context, added, removed }
    let kind: Kind
    let text: String
}

/// The change a single generated file represents against what's on disk.
struct FileDiff: Identifiable {
    enum Change: Equatable { case created, modified, unchanged, deleted }

    /// The intended new state of the file.
    let file: GeneratedFile
    /// Current on-disk contents, or nil if the file does not exist yet.
    let existing: String?
    let change: Change
    /// The full line-by-line diff (context + added + removed), in file order.
    let lines: [FileDiffLine]

    var id: String { file.relativePath }
    var relativePath: String { file.relativePath }
    var displayName: String { file.displayName }

    var added: Int { lines.lazy.filter { $0.kind == .added }.count }
    var removed: Int { lines.lazy.filter { $0.kind == .removed }.count }

    /// Classify and diff a generated file against its current on-disk contents.
    static func make(file: GeneratedFile, existing: String?) -> FileDiff {
        guard let existing else {
            return FileDiff(file: file, existing: nil, change: .created,
                            lines: split(file.contents).map { FileDiffLine(kind: .added, text: $0) })
        }
        if existing == file.contents {
            return FileDiff(file: file, existing: existing, change: .unchanged,
                            lines: split(existing).map { FileDiffLine(kind: .context, text: $0) })
        }
        return FileDiff(file: file, existing: existing, change: .modified,
                        lines: LineDiff.compute(old: existing, new: file.contents))
    }

    /// A file that will be removed on write (a pruned managed agent file). There is
    /// no intended new state, so `file` carries the path with empty contents and
    /// every existing line shows as removed.
    static func deleted(relativePath: String, existing: String?) -> FileDiff {
        FileDiff(file: GeneratedFile(relativePath: relativePath, contents: ""),
                 existing: existing, change: .deleted,
                 lines: split(existing ?? "").map { FileDiffLine(kind: .removed, text: $0) })
    }

    /// Split into lines without inventing a trailing empty line for empty input.
    static func split(_ s: String) -> [String] {
        s.isEmpty ? [] : s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

/// A minimal LCS line differ. Config files are small, so the O(n·m) table is fine
/// and keeps the diff stable and deterministic (good for tests and screenshots).
enum LineDiff {
    static func compute(old: String, new: String) -> [FileDiffLine] {
        let a = FileDiff.split(old)
        let b = FileDiff.split(new)
        let n = a.count, m = b.count
        guard n > 0 else { return b.map { FileDiffLine(kind: .added, text: $0) } }
        guard m > 0 else { return a.map { FileDiffLine(kind: .removed, text: $0) } }

        // dp[i][j] = length of the LCS of a[i...] and b[j...].
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1
                                        : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var out: [FileDiffLine] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                out.append(FileDiffLine(kind: .context, text: a[i])); i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                out.append(FileDiffLine(kind: .removed, text: a[i])); i += 1
            } else {
                out.append(FileDiffLine(kind: .added, text: b[j])); j += 1
            }
        }
        while i < n { out.append(FileDiffLine(kind: .removed, text: a[i])); i += 1 }
        while j < m { out.append(FileDiffLine(kind: .added, text: b[j])); j += 1 }
        return out
    }
}
