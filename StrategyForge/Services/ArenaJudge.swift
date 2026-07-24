//
//  ArenaJudge.swift
//  StrategyForge
//
//  An optional, INDEPENDENT judge for the arena: one read-only pass that scores every
//  contestant's answer against the task and picks a winner by QUALITY, not just cost.
//  Same principle as the loop verifier — the judge is not a contestant's author and only
//  grades. Pure prompt-building + parsing here; the caller runs it via a OneShotRunner.
//  Opt-in, because it spends extra tokens.
//

import Foundation

/// One thing the judge scores: a contestant's final answer, with a stable id + label.
struct ArenaCandidate: Sendable, Equatable {
    let id: String
    let label: String     // e.g. "Claude" or a team name — shown to the judge for context
    let text: String
}

/// The judge's assessment of one candidate.
struct ArenaVerdict: Sendable, Equatable, Identifiable {
    let id: String
    let score: Int        // 0–100
    let reason: String
}

enum ArenaJudge {

    /// Build the impartial-judge prompt. Candidates are labeled by an opaque letter so the
    /// judge scores the ANSWER, not the brand (the id→letter map is applied on parse).
    static func prompt(task: String, candidates: [ArenaCandidate]) -> String {
        var out = """
        You are an impartial expert judge. A task was given to several AI candidates; each \
        produced an answer. Score each answer from 0 to 100 on how well it solves the task \
        — correctness first, then completeness, then clarity. Be strict, specific, and fair; \
        judge the answer's substance, not its length or tone.

        TASK:
        \(task)

        CANDIDATES:

        """
        for (i, c) in candidates.enumerated() {
            let letter = Self.letter(i)
            out += "### Candidate \(letter)\n\(c.text)\n\n"
        }
        out += """
        Return ONLY a JSON object, no prose, in exactly this shape:
        {"verdicts":[{"candidate":"A","score":<0-100>,"reason":"<one sentence>"}]}
        Include every candidate exactly once.
        """
        return out
    }

    /// Parse the judge's JSON back into verdicts, mapping the letters to the candidate ids.
    /// Tolerant: ignores prose around the JSON and unknown/duplicate letters.
    static func parse(_ text: String, candidates: [ArenaCandidate]) -> [ArenaVerdict] {
        guard let data = jsonObjectData(in: text),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["verdicts"] as? [[String: Any]] else { return [] }
        let byLetter = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { (Self.letter($0.offset), $0.element.id) })
        var seen = Set<String>()
        var verdicts: [ArenaVerdict] = []
        for item in raw {
            guard let letter = (item["candidate"] as? String)?.trimmingCharacters(in: .whitespaces).uppercased(),
                  let id = byLetter[letter], !seen.contains(id) else { continue }
            seen.insert(id)
            let score = max(0, min(100, intValue(item["score"])))
            let reason = (item["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            verdicts.append(ArenaVerdict(id: id, score: score, reason: reason))
        }
        return verdicts
    }

    /// The highest-scoring verdict's candidate id (ties → first, stable).
    static func winner(_ verdicts: [ArenaVerdict]) -> String? {
        verdicts.max { $0.score < $1.score }?.id
    }

    // MARK: - Helpers

    /// Candidate letter for index 0→"A", 1→"B", … (wraps with a digit suffix past Z, which
    /// no realistic arena reaches).
    static func letter(_ i: Int) -> String {
        i < 26 ? String(UnicodeScalar(65 + i)!) : "Z\(i)"
    }

    /// The first balanced `{…}` object in a string, as Data (tolerates prose/code fences).
    private static func jsonObjectData(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1; if depth == 0 { return String(text[start...idx]).data(using: .utf8) } }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d.rounded()) }
        if let s = any as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        return 0
    }
}
