//
//  SemanticClassifier.swift
//  StrategyForge
//
//  Phase 2 of the recommender: an on-device SEMANTIC layer that catches tasks the
//  keyword classifier misses (paraphrases, unusual wording). It uses Apple's bundled
//  word embeddings (NaturalLanguage) — fully local, private, and DETERMINISTIC (the
//  vectors are fixed) — to match a task against a small set of prototype phrases per
//  intent by cosine similarity.
//
//  It is an ASSIST, never authoritative: `heuristicShape` only consults it when the
//  keyword read is low-confidence, and only adopts its intent above a similarity
//  threshold. When embeddings are unavailable (older OS / missing asset) every entry
//  point returns nil and the app falls back cleanly to the keyword classifier — so this
//  can never regress the keyword path.
//

import Foundation
import NaturalLanguage

enum SemanticClassifier {

    /// Prototype phrases per intent. Kept short and canonical; the embedding of the
    /// task is compared to the best-matching prototype in each intent's set.
    private static let prototypes: [(StrategyGenerator.TaskIntent, [String])] = [
        (.understand, ["understand how the code works", "explore an unfamiliar codebase",
                       "figure out how the system behaves", "study the architecture"]),
        (.decide,     ["decide the architecture", "compare the trade-offs between options",
                       "choose the best design approach", "weigh alternatives and pick one"]),
        (.review,     ["review the code for correctness", "audit for security problems",
                       "verify the quality before shipping", "check for bugs and regressions"]),
        (.triage,     ["triage the incoming issues", "classify and route each request",
                       "sort and dispatch the tickets", "categorize the backlog"]),
        (.change,     ["refactor and change the code", "migrate to a new library",
                       "rename and reorganize the modules", "clean up and modernize"]),
        (.build,      ["implement a new feature", "build and create new functionality",
                       "add a capability to the app", "write a new component"]),
        (.harden,     ["attack and try to break the system", "harden the security",
                       "red-team the application", "stress and exploit weaknesses"]),
        (.quick,      ["a quick small experiment", "try something fast and simple",
                       "a tiny throwaway test"]),
    ]

    /// Best-matching intent for a task, with its cosine score (0…1), using on-device
    /// word embeddings. Returns nil when embeddings are unavailable or the task shares no
    /// in-vocabulary words with any prototype. Deterministic for a given OS model.
    static func bestIntent(for task: String) -> (intent: StrategyGenerator.TaskIntent, score: Double)? {
        let language = detectLanguage(task)
        guard let emb = embedding(for: language),
              let taskVec = sentenceVector(task, emb: emb) else { return nil }

        var best: (StrategyGenerator.TaskIntent, Double)?
        for (intent, phrases) in prototypes {
            var top = 0.0
            for phrase in phrases {
                guard let v = sentenceVector(phrase, emb: emb) else { continue }
                top = max(top, cosine(taskVec, v))
            }
            if best == nil || top > best!.1 { best = (intent, top) }
        }
        return best.map { (intent: $0.0, score: $0.1) }
    }

    // MARK: - Embedding plumbing

    /// Cache the word-embedding models (loading is the expensive part), keyed by code.
    /// Guarded by a lock because `bestIntent` can be reached from concurrent async
    /// contexts (multiple recommendation Tasks) — an unsynchronized Dictionary read/write
    /// there would be a data race.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NLEmbedding?] = [:]
    private static func embedding(for language: NLLanguage) -> NLEmbedding? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[language.rawValue] { return hit }
        let model = NLEmbedding.wordEmbedding(for: language)
        cache[language.rawValue] = model
        return model
    }

    /// English or Spanish (the app's two languages); defaults to English. Embeddings are
    /// per-language, so we match the task's language before comparing to prototypes.
    private static func detectLanguage(_ text: String) -> NLLanguage {
        let r = NLLanguageRecognizer()
        r.processString(text)
        return r.dominantLanguage == .spanish ? .spanish : .english
    }

    /// Mean of the in-vocabulary word vectors — a cheap, deterministic sentence vector.
    private static func sentenceVector(_ s: String, emb: NLEmbedding) -> [Double]? {
        let words = s.lowercased().split { !$0.isLetter }.map(String.init)
        var sum: [Double] = []
        var n = 0
        for w in words {
            guard let v = emb.vector(for: w) else { continue }
            if sum.isEmpty { sum = v } else { for i in 0..<min(sum.count, v.count) { sum[i] += v[i] } }
            n += 1
        }
        guard n > 0, !sum.isEmpty else { return nil }
        for i in 0..<sum.count { sum[i] /= Double(n) }
        return sum
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = na.squareRoot() * nb.squareRoot()
        return denom > 0 ? dot / denom : 0
    }
}
