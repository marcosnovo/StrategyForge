//
//  DiffTests.swift
//  StrategyForgeTests
//
//  Unit tests for the pre-write diff: created / modified / unchanged classification
//  and the LCS line differ.
//

import Testing
import Foundation
@testable import StrategyForge

struct FileDiffTests {

    @Test func createdWhenNoExistingFile() {
        let file = GeneratedFile(relativePath: "CLAUDE.md", contents: "a\nb\nc")
        let diff = FileDiff.make(file: file, existing: nil)
        #expect(diff.change == .created)
        #expect(diff.added == 3)
        #expect(diff.removed == 0)
        #expect(diff.lines.allSatisfy { $0.kind == .added })
    }

    @Test func unchangedWhenIdentical() {
        let file = GeneratedFile(relativePath: "x.md", contents: "one\ntwo")
        let diff = FileDiff.make(file: file, existing: "one\ntwo")
        #expect(diff.change == .unchanged)
        #expect(diff.added == 0)
        #expect(diff.removed == 0)
        #expect(diff.lines.allSatisfy { $0.kind == .context })
    }

    @Test func modifiedCountsAddedAndRemoved() {
        let file = GeneratedFile(relativePath: "x.md", contents: "one\nTWO\nthree")
        let diff = FileDiff.make(file: file, existing: "one\ntwo\nthree")
        #expect(diff.change == .modified)
        #expect(diff.added == 1)   // "TWO"
        #expect(diff.removed == 1) // "two"
        // Unchanged lines are preserved as context on both sides.
        #expect(diff.lines.contains(FileDiffLine(kind: .context, text: "one")))
        #expect(diff.lines.contains(FileDiffLine(kind: .context, text: "three")))
    }

    @Test func emptyContentsProducesNoLines() {
        let file = GeneratedFile(relativePath: "x.md", contents: "")
        let diff = FileDiff.make(file: file, existing: nil)
        #expect(diff.change == .created)
        #expect(diff.lines.isEmpty)
    }

    @Test func deletedShowsEveryLineRemoved() {
        let diff = FileDiff.deleted(relativePath: ".claude/agents/old-worker.md",
                                    existing: "line 1\nline 2")
        #expect(diff.change == .deleted)
        #expect(diff.relativePath == ".claude/agents/old-worker.md")
        #expect(diff.removed == 2)
        #expect(diff.added == 0)
        #expect(diff.lines.allSatisfy { $0.kind == .removed })
    }
}

struct LineDiffTests {

    @Test func pureInsertionAddsOnlyTheNewLine() {
        let lines = LineDiff.compute(old: "a\nc", new: "a\nb\nc")
        #expect(lines.filter { $0.kind == .added } == [FileDiffLine(kind: .added, text: "b")])
        #expect(lines.filter { $0.kind == .removed }.isEmpty)
        // Order and context are preserved.
        #expect(lines == [
            FileDiffLine(kind: .context, text: "a"),
            FileDiffLine(kind: .added, text: "b"),
            FileDiffLine(kind: .context, text: "c"),
        ])
    }

    @Test func pureDeletionRemovesOnlyTheDroppedLine() {
        let lines = LineDiff.compute(old: "a\nb\nc", new: "a\nc")
        #expect(lines.filter { $0.kind == .removed } == [FileDiffLine(kind: .removed, text: "b")])
        #expect(lines.filter { $0.kind == .added }.isEmpty)
    }

    @Test func fromEmptyIsAllAdded() {
        let lines = LineDiff.compute(old: "", new: "x\ny")
        #expect(lines == [
            FileDiffLine(kind: .added, text: "x"),
            FileDiffLine(kind: .added, text: "y"),
        ])
    }

    @Test func toEmptyIsAllRemoved() {
        let lines = LineDiff.compute(old: "x\ny", new: "")
        #expect(lines.allSatisfy { $0.kind == .removed })
        #expect(lines.count == 2)
    }
}
