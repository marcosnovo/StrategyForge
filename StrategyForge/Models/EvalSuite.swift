//
//  EvalSuite.swift
//  StrategyForge
//
//  Evals for a team (the gap Karpathy flags: "89% have observability, only 52% have
//  evals"). A suite is a set of test scenarios; running it scores the team with the same
//  independent read-only judge the loop verifier uses, and gates "ready" on a pass rate.
//  Pure data — the runner lives in Services/EvalRunner.swift.
//

import Foundation

/// What kind of behavior a scenario probes — drives grouping in the report.
enum EvalCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case answersCorrectly   // the team should answer well
    case refusesWhenUnknown // out of scope → should say it doesn't know, not hallucinate
    case multiHop           // needs combining multiple pieces
    case citation           // must ground / cite its sources

    var id: String { rawValue }

    /// Localization key for the category label.
    var labelKey: String { "eval.category.\(rawValue)" }
}

/// One test case: a prompt plus the behavior a judge should verify in the response.
struct EvalScenario: Codable, Identifiable, Hashable {
    var id: UUID
    var prompt: String
    /// The behavior the judge checks the team's answer against (e.g. "cites a source",
    /// "declines because the answer isn't in scope").
    var expectation: String
    var category: EvalCategory

    init(id: UUID = UUID(), prompt: String, expectation: String, category: EvalCategory) {
        self.id = id
        self.prompt = prompt
        self.expectation = expectation
        self.category = category
    }
}

/// A reusable suite attached to a `Strategy`.
struct EvalSuite: Codable, Identifiable, Hashable {
    var id: UUID
    var scenarios: [EvalScenario]
    /// Pass-rate (0…1) a run must reach for the team to count as "ready" / a loop to be
    /// safe to schedule. Default 0.8.
    var passThreshold: Double

    init(id: UUID = UUID(), scenarios: [EvalScenario] = [], passThreshold: Double = 0.8) {
        self.id = id
        self.scenarios = scenarios
        self.passThreshold = passThreshold
    }

    // Tolerant: an older/partial suite still decodes with sensible defaults.
    enum CodingKeys: String, CodingKey { case id, scenarios, passThreshold }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        scenarios = (try? c.decodeIfPresent([EvalScenario].self, forKey: .scenarios) ?? []) ?? []
        passThreshold = (try? c.decodeIfPresent(Double.self, forKey: .passThreshold) ?? 0.8) ?? 0.8
    }
}

/// The verdict for a single scenario after a run.
struct EvalResult: Identifiable, Hashable, Sendable {
    var scenarioID: UUID
    var passed: Bool
    /// The judge's short reason — for a fail, ideally what to change (traced to the
    /// instruction), echoing the article's "removing that line will solve this".
    var reason: String

    var id: UUID { scenarioID }
}

/// The outcome of running a whole suite.
struct EvalRun: Sendable {
    var results: [EvalResult]
    var threshold: Double

    var total: Int { results.count }
    var passed: Int { results.filter(\.passed).count }
    /// Fraction passed (0…1); 0 for an empty run.
    var passRate: Double { total == 0 ? 0 : Double(passed) / Double(total) }
    /// The gate: did the run clear the suite's threshold? An empty run never passes.
    var meetsThreshold: Bool { total > 0 && passRate >= threshold }
}
