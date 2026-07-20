//
//  ModelJSON.swift
//  StrategyForge
//
//  The one tolerant "extract the first JSON blob" parse shared by every service that
//  asks a model for strict JSON and may get prose/fences around it anyway
//  (DiffReviewer.parseFindings, EvalRunner.parseScenarios/parseVerdict,
//  MetaOrchestrator.parsePlan). Slices from the first opening bracket to the LAST
//  closing one and parses; returns nil on any failure — each caller keeps its own
//  fallback (empty findings, fallback plan, failed verdict, …).
//

import Foundation

enum ModelJSON {

    /// The first `[...]` in `text` parsed as an array of JSON objects, or nil.
    static func firstArray(in text: String) -> [[String: Any]]? {
        blob(in: text, open: "[", close: "]") as? [[String: Any]]
    }

    /// The first `{...}` in `text` parsed as a JSON object, or nil.
    static func firstObject(in text: String) -> [String: Any]? {
        blob(in: text, open: "{", close: "}") as? [String: Any]
    }

    /// Slice `text` from the first `open` to the last `close` and JSON-parse it.
    private static func blob(in text: String, open: Character, close: Character) -> Any? {
        guard let start = text.firstIndex(of: open), let end = text.lastIndex(of: close),
              start < end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
