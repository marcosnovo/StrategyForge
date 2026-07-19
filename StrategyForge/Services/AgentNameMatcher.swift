//
//  AgentNameMatcher.swift
//  StrategyForge
//
//  Loose matching between a diagram node title and a streamed agent name (a
//  subagent_type slug or a free-text description). This is domain logic — the run
//  stream and the diagram both key off it — so it lives in Services, not inside a
//  SwiftUI view (it used to hang off StrategyDiagramView, a Views→domain inversion).
//

import Foundation

enum AgentNameMatcher {
    /// True when two agent/role names refer to the same teammate after normalizing to
    /// letters+digits and testing substring containment either way.
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }
        let na = norm(a), nb = norm(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na.contains(nb) || nb.contains(na)
    }
}
