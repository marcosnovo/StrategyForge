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
