//
//  DiffHunkTests.swift
//  StrategyForgeTests
//
//  Unit tests for grouping a flat parsed unified diff into structured hunks, and for the
//  word-level intraline emphasis both diff views share.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct DiffHunkTests {

    /// A two-hunk unified diff — the shape `git diff` emits for edits in two places.
    private let twoHunkDiff = """
    diff --git a/foo.swift b/foo.swift
    index 111..222 100644
    --- a/foo.swift
    +++ b/foo.swift
    @@ -1,3 +1,3 @@
     let a = 1
    -let b = 2
    +let b = 20
     let c = 3
    @@ -10,2 +10,3 @@
     func done() {}
    +// added
     let z = 9
    """

    @Test func groupsEachAtMarkerIntoItsOwnHunk() {
        let hunks = DiffHunks.group(CodeGit.parse(twoHunkDiff))
        #expect(hunks.count == 2)
        #expect(hunks[0].header.hasPrefix("@@ -1,3 +1,3 @@"))
        #expect(hunks[1].header.hasPrefix("@@ -10,2 +10,3 @@"))
    }

    @Test func countsInsertionsAndDeletionsPerHunk() {
        let hunks = DiffHunks.group(CodeGit.parse(twoHunkDiff))
        #expect(hunks[0].insertions == 1)   // let b = 20
        #expect(hunks[0].deletions == 1)    // let b = 2
        #expect(hunks[1].insertions == 1)   // // added
        #expect(hunks[1].deletions == 0)
        let allChange = hunks.allSatisfy(\.hasChange)
        #expect(allChange)
    }

    @Test func headerLinesNeverLeakIntoHunkBodies() {
        let hunks = DiffHunks.group(CodeGit.parse(twoHunkDiff))
        let noHeaders = hunks.allSatisfy { h in h.lines.allSatisfy { $0.kind != .hunk } }
        #expect(noHeaders)
    }

    @Test func anchorPointsAtTheHunksFirstNewLine() {
        let hunks = DiffHunks.group(CodeGit.parse(twoHunkDiff))
        // First body line of hunk 1 is context "let a = 1" at new line 1.
        #expect(hunks[0].anchorNewLine == 1)
        // Hunk 2 starts at new line 10.
        #expect(hunks[1].anchorNewLine == 10)
    }

    @Test func leadingBodyWithoutHeaderStillFormsAHunk() {
        // A stub "new file" diff the parser may emit with no @@ marker.
        let lines = [
            DiffLine(id: 0, kind: .add, oldNumber: nil, newNumber: 1, text: "hello"),
            DiffLine(id: 1, kind: .add, oldNumber: nil, newNumber: 2, text: "world"),
        ]
        let hunks = DiffHunks.group(lines)
        #expect(hunks.count == 1)
        #expect(hunks[0].header.isEmpty)
        #expect(hunks[0].insertions == 2)
    }

    @Test func emptyDiffYieldsNoHunks() {
        #expect(DiffHunks.group([]).isEmpty)
    }

    @Test func unifiedPatchRoundTripsPrefixesAndHeaders() {
        let hunks = DiffHunks.group(CodeGit.parse(twoHunkDiff))
        let patch = hunks[0].unifiedPatch(relPath: "foo.swift")
        #expect(patch != nil)
        let p = patch ?? ""
        // File headers with a/ b/ paths for `git apply -p1`.
        #expect(p.contains("diff --git a/foo.swift b/foo.swift"))
        #expect(p.contains("--- a/foo.swift"))
        #expect(p.contains("+++ b/foo.swift"))
        // The @@ header is preserved verbatim.
        #expect(p.contains("@@ -1,3 +1,3 @@"))
        // Line prefixes are restored: context=space, del=-, add=+.
        #expect(p.contains("\n let a = 1\n"))
        #expect(p.contains("\n-let b = 2\n"))
        #expect(p.contains("\n+let b = 20\n"))
    }

    @Test func unifiedPatchRefusesContextOnlyOrHeaderless() {
        // A context-only hunk has no change to apply.
        let ctx = DiffHunk(id: 0, header: "@@ -1,1 +1,1 @@",
                           lines: [DiffLine(id: 0, kind: .context, oldNumber: 1, newNumber: 1, text: "x")])
        #expect(ctx.unifiedPatch(relPath: "a.txt") == nil)
        // A headerless (stub) hunk can't be reconstructed into a valid patch.
        let headerless = DiffHunk(id: 0, header: "",
                                  lines: [DiffLine(id: 0, kind: .add, oldNumber: nil, newNumber: 1, text: "y")])
        #expect(headerless.unifiedPatch(relPath: "a.txt") == nil)
    }
}

@MainActor
struct DiffEmphasisTests {

    @Test func pinpointsTheChangedTokenBetweenPairedLines() {
        let lines = [
            DiffLine(id: 0, kind: .del, oldNumber: 1, newNumber: nil, text: "let b = 2"),
            DiffLine(id: 1, kind: .add, oldNumber: nil, newNumber: 1, text: "let b = 3"),
        ]
        let map = DiffEmphasis.compute(lines)
        // Both sides emphasise ONLY the changed final character ("2" ↔ "3"), after "let b = ".
        #expect(map[0] == 8..<9)
        #expect(map[1] == 8..<9)
    }

    @Test func skipsWhenLinesAreEqualOrUnpaired() {
        // A lone deletion has no add to pair with.
        let lines = [DiffLine(id: 0, kind: .del, oldNumber: 1, newNumber: nil, text: "gone")]
        #expect(DiffEmphasis.compute(lines).isEmpty)
    }

    @Test func skipsNearTotalRewrites() {
        // Completely different lines: the row background already signals it, so no word wash.
        #expect(DiffEmphasis.wordDiff("abcdef", "zyxwvu") == nil)
    }
}
