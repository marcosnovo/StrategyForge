//
//  ModelJSONTests.swift
//  StrategyForgeTests
//
//  Tests for the shared tolerant "first JSON blob" extraction that DiffReviewer,
//  EvalRunner, and MetaOrchestrator all parse model replies through. The per-parser
//  tests cover each caller's fallback; these pin the extraction itself so hardening
//  can't silently drift between callers again.
//

import Testing
import Foundation
@testable import Coral

struct ModelJSONTests {

    @Test func extractsAnArrayWrappedInProseAndFences() {
        let text = """
        Sure! Here's the JSON you asked for:
        ```json
        [{"a": 1}, {"b": "two"}]
        ```
        Let me know if you need anything else.
        """
        let arr = ModelJSON.firstArray(in: text)
        #expect(arr?.count == 2)
        #expect(arr?.first?["a"] as? Int == 1)
        #expect(arr?.last?["b"] as? String == "two")
    }

    @Test func extractsAnObjectWrappedInProse() {
        let obj = ModelJSON.firstObject(in: "verdict follows {\"pass\": true, \"reason\": \"ok\"} done")
        #expect(obj?["pass"] as? Bool == true)
        #expect(obj?["reason"] as? String == "ok")
    }

    @Test func bareJSONParsesUnchanged() {
        #expect(ModelJSON.firstArray(in: "[]")?.isEmpty == true)
        #expect(ModelJSON.firstObject(in: "{}")?.isEmpty == true)
    }

    @Test func spansFirstOpenToLastCloseAcrossMultipleBlobs() {
        // Historic behavior: slice from the FIRST opener to the LAST closer — two
        // arrays separated by prose make the slice invalid JSON, so this is nil,
        // not the first array.
        #expect(ModelJSON.firstArray(in: "[{\"a\":1}] and also [{\"b\":2}]") == nil)
    }

    @Test func garbageAndMismatchedBracketsYieldNil() {
        #expect(ModelJSON.firstArray(in: "no json here") == nil)
        #expect(ModelJSON.firstArray(in: "] backwards [") == nil)      // last "]" before first "["
        #expect(ModelJSON.firstArray(in: "[ truncated") == nil)
        #expect(ModelJSON.firstObject(in: "} backwards {") == nil)
        #expect(ModelJSON.firstObject(in: "not { valid json }") == nil)
    }

    @Test func arrayOfNonObjectsIsNil() {
        // The cast is to [[String: Any]]; a bare scalar array doesn't qualify.
        #expect(ModelJSON.firstArray(in: "[1, 2, 3]") == nil)
    }
}
