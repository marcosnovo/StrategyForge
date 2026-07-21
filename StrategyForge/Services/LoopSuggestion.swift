//
//  LoopSuggestion.swift
//  StrategyForge
//
//  Detects when a chat message reads like a REPEATABLE or GOAL-shaped task — the moment
//  Coral should contextually offer "Run this as a loop?" instead of making loops a
//  top-level thing the user must discover. Pure + testable.
//

import Foundation

enum LoopSuggestion {
    /// Schedule / recurrence / iterate-until cues (English + Spanish). Short words that
    /// are prefixes of common words (e.g. "every" in "everyone") carry a trailing space
    /// so they only match the recurrence sense ("every morning").
    private static let cues: [String] = [
        // recurrence / schedule
        "every ", "each day", "each morning", "daily", "weekly", "hourly", "nightly",
        "on a schedule", "recurring", "repeat", "keep an eye", "watch for", "monitor",
        // iterate-until / autonomy
        "until it passes", "until all", "keep trying", "keep going until", "over and over",
        // español
        "cada día", "cada mañana", "cada hora", "a diario", "diariamente", "semanal",
        "programad", "recurrente", "repite", "repetir", "vigila", "monitoriza",
        "hasta que pase", "hasta que todo", "sigue intentando", "una y otra vez",
    ]

    /// True when the text looks like something worth running on a loop.
    static func looksRepeatable(_ text: String) -> Bool {
        let t = " " + text.lowercased() + " "
        return cues.contains { t.contains($0) }
    }
}
