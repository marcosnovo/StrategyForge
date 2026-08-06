//
//  DiffHunk.swift
//  StrategyForge
//
//  A structured hunk view over the flat `[DiffLine]` the diff parser produces. SOTA diff
//  viewers (Zed/GitHub/VS Code) reason in HUNKS — the @@-delimited change blocks — not raw
//  lines: it's what lets you jump between changes and, later, stage/revert one block at a
//  time. Grouping is pure so it's unit-tested and cheap to recompute per selected file.
//

import Foundation

/// One @@-delimited change block: its header line plus the body lines that belong to it.
struct DiffHunk: Identifiable, Equatable {
    /// Index of the hunk within the file (0-based) — also its stable identity.
    let id: Int
    /// The raw "@@ -a,b +c,d @@ …" header, or "" for a leading block with no header
    /// (e.g. a brand-new file the parser emitted without a hunk marker).
    let header: String
    /// Body lines (add / del / context) in order; never includes the header line itself.
    let lines: [DiffLine]

    var insertions: Int { lines.reduce(0) { $0 + ($1.kind == .add ? 1 : 0) } }
    var deletions: Int { lines.reduce(0) { $0 + ($1.kind == .del ? 1 : 0) } }
    /// A hunk is "empty" if it carries no actual change (only context) — worth skipping in nav.
    var hasChange: Bool { insertions > 0 || deletions > 0 }

    /// The new-file line to scroll to when jumping here: the first added/context line's new
    /// number, falling back to the first old number for a pure deletion.
    var anchorNewLine: Int? {
        lines.compactMap(\.newNumber).first ?? lines.compactMap(\.oldNumber).first
    }
    /// The header line's own id (for scroll targeting the @@ row when present).
    var headerLineID: DiffLine.ID?

    /// Reconstruct a standalone, `git apply`-able unified-diff patch for JUST this hunk. Re-adds
    /// the per-line prefixes the parser stripped (context=" ", add="+", del="-") and prepends the
    /// `diff --git` / `---` / `+++` file headers with `a/`/`b/` paths (so `git apply -p1` works).
    /// Pure, so it's unit-tested; the working tree must still match the hunk's context for apply
    /// to succeed (git verifies this and fails cleanly otherwise).
    func unifiedPatch(relPath: String) -> String? {
        guard !header.isEmpty, hasChange else { return nil }
        var out = "diff --git a/\(relPath) b/\(relPath)\n"
        out += "--- a/\(relPath)\n+++ b/\(relPath)\n"
        out += header + "\n"
        for l in lines {
            switch l.kind {
            case .add:     out += "+" + l.text + "\n"
            case .del:     out += "-" + l.text + "\n"
            case .context: out += " " + l.text + "\n"
            case .hunk:    break   // never present in a hunk body
            }
        }
        return out
    }
}

enum DiffHunks {
    /// Group a flat parsed diff into hunks. Lines that appear before the first `@@` header —
    /// which happens for new/stub files — are collected into a leading headerless hunk so no
    /// change is lost.
    static func group(_ lines: [DiffLine]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var header = ""
        var headerID: DiffLine.ID? = nil
        var body: [DiffLine] = []
        var started = false

        func flush() {
            // Emit whenever we've either seen a header or accumulated leading body lines.
            guard started || !body.isEmpty else { return }
            hunks.append(DiffHunk(id: hunks.count, header: header, lines: body, headerLineID: headerID))
            header = ""; headerID = nil; body = []
        }

        for l in lines {
            if l.kind == .hunk {
                flush()
                header = l.text; headerID = l.id; started = true
            } else {
                body.append(l)
            }
        }
        flush()
        return hunks
    }
}
