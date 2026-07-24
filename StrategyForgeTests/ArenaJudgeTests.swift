//
//  ArenaJudgeTests.swift
//  StrategyForgeTests
//
//  The independent arena judge: the prompt anonymizes candidates by letter, and the
//  parser tolerantly maps the judge's JSON (even wrapped in prose / code fences) back to
//  candidate ids, clamps scores, and the winner is the highest score.
//

import Testing
import Foundation
@testable import Coral

struct ArenaJudgeTests {

    private let candidates = [
        ArenaCandidate(id: "claude:opus", label: "Claude", text: "Answer one."),
        ArenaCandidate(id: "openai:gpt-5", label: "GPT-5", text: "Answer two."),
        ArenaCandidate(id: "gemini:pro", label: "Gemini", text: "Answer three."),
    ]

    @Test func promptAnonymizesByLetterAndIncludesTaskAndEveryAnswer() {
        let p = ArenaJudge.prompt(task: "Sort a list in O(n log n).", candidates: candidates)
        #expect(p.contains("Sort a list in O(n log n)."))
        #expect(p.contains("### Candidate A"))
        #expect(p.contains("### Candidate C"))
        #expect(p.contains("Answer two."))
        // The brand names are NOT shown to the judge (it scores substance, by letter).
        #expect(!p.contains("GPT-5"))
        #expect(!p.contains("Claude"))
    }

    @Test func parseMapsLettersToIdsClampsAndToleratesProseAndFences() {
        let reply = """
        Sure, here's my assessment:
        ```json
        {"verdicts":[
          {"candidate":"A","score":150,"reason":"best"},
          {"candidate":"b","score":40,"reason":"ok"},
          {"candidate":"C","score":-5,"reason":"weak"},
          {"candidate":"Z","score":99,"reason":"unknown letter ignored"}
        ]}
        ```
        Hope that helps!
        """
        let v = ArenaJudge.parse(reply, candidates: candidates)
        #expect(v.count == 3)                                  // unknown "Z" dropped
        #expect(v.first { $0.id == "claude:opus" }?.score == 100)   // clamped from 150
        #expect(v.first { $0.id == "openai:gpt-5" }?.score == 40)   // lowercase "b" mapped
        #expect(v.first { $0.id == "gemini:pro" }?.score == 0)      // clamped from -5
        #expect(ArenaJudge.winner(v) == "claude:opus")             // highest score wins
    }

    @Test func parseReturnsEmptyOnGarbage() {
        #expect(ArenaJudge.parse("no json here", candidates: candidates).isEmpty)
        #expect(ArenaJudge.winner([]) == nil)
    }

    @Test func duplicateLettersKeepFirst() {
        let reply = #"{"verdicts":[{"candidate":"A","score":70,"reason":"x"},{"candidate":"A","score":10,"reason":"y"}]}"#
        let v = ArenaJudge.parse(reply, candidates: candidates)
        #expect(v.count == 1)
        #expect(v[0].score == 70)
    }
}
