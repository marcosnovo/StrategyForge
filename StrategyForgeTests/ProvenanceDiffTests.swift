//
//  ProvenanceDiffTests.swift
//  StrategyForgeTests
//
//  The per-line diff annotator: added lines map to their new-file line number via the
//  hunk header, and thus to the provider that wrote each line.
//

import Testing
import Foundation
@testable import Coral

struct ProvenanceDiffTests {

    private let gem = EditProvenance(agent: "backend", model: "Gemini 2.5 Pro", provider: .gemini)
    private let oai = EditProvenance(agent: "frontend", model: "GPT-5", provider: .openai)

    @Test func addedLinesAreTaggedWithTheirProvider() {
        // A new file "shared.txt" with two added lines: line 1 by gemini, line 2 by openai.
        let diff = """
        diff --git a/shared.txt b/shared.txt
        new file mode 100644
        --- /dev/null
        +++ b/shared.txt
        @@ -0,0 +1,2 @@
        +line by gemini
        +line by openai
        """
        let authors: [String: [EditProvenance?]] = ["shared.txt": [gem, oai]]
        let annotated = ProvenanceDiff.annotate(diff, lineAuthors: authors)

        let added = annotated.filter { $0.kind == .added }
        #expect(added.count == 2)
        #expect(added[0].provider == .gemini)
        #expect(added[1].provider == .openai)
        // File + hunk headers are classified, never colored.
        #expect(annotated.contains { $0.kind == .hunkHeader && $0.text.hasPrefix("@@") })
        #expect(annotated.contains { $0.kind == .fileHeader && $0.text.contains("shared.txt") })
    }

    @Test func hunkOffsetsMapAddedLinesToTheRightAuthor() {
        // Change at new-file line 3: only line 3 is added, authored by openai.
        let diff = """
        +++ b/f.swift
        @@ -2,2 +2,3 @@
         context a
        +inserted line
         context b
        """
        // f.swift final lines: [1,2,3,4] where line 3 (index 2) is openai's insert.
        let authors: [String: [EditProvenance?]] = ["f.swift": [gem, gem, oai, gem]]
        let annotated = ProvenanceDiff.annotate(diff, lineAuthors: authors)
        let added = annotated.filter { $0.kind == .added }
        #expect(added.count == 1)
        #expect(added[0].provider == .openai)   // mapped to new-file line 3
    }

    @Test func unknownFileOrMissingAuthorsLeavesProviderNil() {
        let diff = "+++ b/x.txt\n@@ -0,0 +1,1 @@\n+hello"
        let annotated = ProvenanceDiff.annotate(diff, lineAuthors: [:])
        #expect(annotated.first { $0.kind == .added }?.provider == nil)
    }
}
