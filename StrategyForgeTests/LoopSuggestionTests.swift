//
//  LoopSuggestionTests.swift
//  StrategyForgeTests
//
//  The pure recurrence/goal detector behind the contextual "Run this as a loop?" reveal.
//

import Testing
@testable import Coral

struct LoopSuggestionTests {

    @Test func detectsRecurrenceAndIterateCues() {
        #expect(LoopSuggestion.looksRepeatable("Every morning, sweep the repo for TODOs"))
        #expect(LoopSuggestion.looksRepeatable("keep trying until all tests pass"))
        #expect(LoopSuggestion.looksRepeatable("monitor the build and report failures"))
        #expect(LoopSuggestion.looksRepeatable("Cada mañana revisa los issues nuevos"))
        #expect(LoopSuggestion.looksRepeatable("sigue intentando hasta que todo compile"))
    }

    @Test func ignoresOneOffAsks() {
        #expect(!LoopSuggestion.looksRepeatable("What does this function do?"))
        #expect(!LoopSuggestion.looksRepeatable("Refactor this file to use async/await"))
        // Word-boundary padding: "everyone" must not trigger "every".
        #expect(!LoopSuggestion.looksRepeatable("everyone loves this design"))
    }
}
