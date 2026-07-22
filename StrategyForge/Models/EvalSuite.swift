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
    case adversarial        // red-team: jailbreak / prompt injection / exfil / tool abuse

    var id: String { rawValue }

    /// Red-team scenarios probe SAFETY (resisting attack), so a pass means "held", and
    /// they belong to the safety dimension of the rubric.
    var isAdversarial: Bool { self == .adversarial }

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
    /// What the team's PATH should look like — which subagents/tools it should (or must
    /// NOT) use — so a right answer for the wrong reason still fails (article #4). Empty
    /// = don't grade the trajectory for this scenario.
    var trajectoryExpectation: String

    init(id: UUID = UUID(), prompt: String, expectation: String, category: EvalCategory,
         trajectoryExpectation: String = "") {
        self.id = id
        self.prompt = prompt
        self.expectation = expectation
        self.category = category
        self.trajectoryExpectation = trajectoryExpectation
    }

    // Tolerant: older suites without a trajectory expectation still decode.
    enum CodingKeys: String, CodingKey { case id, prompt, expectation, category, trajectoryExpectation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        expectation = (try? c.decode(String.self, forKey: .expectation)) ?? ""
        category = (try? c.decode(EvalCategory.self, forKey: .category)) ?? .answersCorrectly
        trajectoryExpectation = (try? c.decodeIfPresent(String.self, forKey: .trajectoryExpectation) ?? "") ?? ""
    }
}

/// A reusable suite attached to a `Strategy`.
struct EvalSuite: Codable, Identifiable, Hashable {
    var id: UUID
    var scenarios: [EvalScenario]
    /// Pass-rate (0…1) a run must reach for the team to count as "ready" / a loop to be
    /// safe to schedule. Default 0.8.
    var passThreshold: Double
    /// The last run's per-scenario verdict (scenarioID.uuidString → passed), kept so a
    /// re-run after a prompt/model change can diff against it — "prompts have no type
    /// system" (article #6, regression). Empty until the first run.
    var baseline: [String: Bool]

    init(id: UUID = UUID(), scenarios: [EvalScenario] = [], passThreshold: Double = 0.8,
         baseline: [String: Bool] = [:]) {
        self.id = id
        self.scenarios = scenarios
        self.passThreshold = passThreshold
        self.baseline = baseline
    }

    // Tolerant: an older/partial suite still decodes with sensible defaults.
    enum CodingKeys: String, CodingKey { case id, scenarios, passThreshold, baseline }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        scenarios = (try? c.decodeIfPresent([EvalScenario].self, forKey: .scenarios) ?? []) ?? []
        passThreshold = (try? c.decodeIfPresent(Double.self, forKey: .passThreshold) ?? 0.8) ?? 0.8
        baseline = (try? c.decodeIfPresent([String: Bool].self, forKey: .baseline) ?? [:]) ?? [:]
    }
}

/// Regression delta between a suite's saved baseline and a fresh run (article #6): which
/// scenarios went pass→fail (regressions) and fail→pass (fixes), matched by scenario id.
struct EvalRegression: Sendable, Equatable {
    var regressed: [UUID]   // were passing, now failing — the ones that should block a ship
    var fixed: [UUID]       // were failing, now passing
    var hasBaseline: Bool

    static func between(baseline: [String: Bool], run: EvalRun) -> EvalRegression {
        guard !baseline.isEmpty else { return EvalRegression(regressed: [], fixed: [], hasBaseline: false) }
        var regressed: [UUID] = [], fixed: [UUID] = []
        for r in run.results {
            guard let was = baseline[r.scenarioID.uuidString] else { continue }
            let now = r.effectivePassed
            if was && !now { regressed.append(r.scenarioID) }
            if !was && now { fixed.append(r.scenarioID) }
        }
        return EvalRegression(regressed: regressed, fixed: fixed, hasBaseline: true)
    }
}

extension EvalRun {
    /// The pass-map to persist as the next run's baseline.
    var baselineMap: [String: Bool] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.scenarioID.uuidString, $0.effectivePassed) })
    }
}

/// The verdict for a single scenario after a run.
struct EvalResult: Identifiable, Hashable, Sendable {
    var scenarioID: UUID
    var passed: Bool
    /// The judge's short reason — for a fail, ideally what to change (traced to the
    /// instruction), echoing the article's "removing that line will solve this".
    var reason: String
    /// Per-dimension rubric scores (0…5): a single pass/fail hides WHICH part got worse,
    /// so the judge also rates correctness / grounding / safety separately (article #3).
    /// Empty when the judge returned none.
    var scores: [String: Int] = [:]
    /// Whether the team's PATH (tools/subagents it took) matched the scenario's trajectory
    /// expectation — nil when the scenario didn't ask for one (article #4).
    var trajectoryPassed: Bool? = nil
    var trajectoryReason: String = ""
    /// A human's override of the judge's verdict, for calibration — nil = not reviewed.
    /// Lets you catch a judge that quietly drifts (article #8).
    var humanVerdict: Bool? = nil

    var id: UUID { scenarioID }

    /// The verdict that counts: the human's override when present, else the judge's.
    var effectivePassed: Bool { humanVerdict ?? passed }
}

/// The outcome of running a whole suite.
struct EvalRun: Sendable {
    var results: [EvalResult]
    var threshold: Double

    var total: Int { results.count }
    /// Counts the EFFECTIVE verdict (a human override wins over the judge), so calibrating
    /// a wrong verdict moves the gate.
    var passed: Int { results.filter(\.effectivePassed).count }
    /// Fraction passed (0…1); 0 for an empty run.
    var passRate: Double { total == 0 ? 0 : Double(passed) / Double(total) }
    /// The gate: did the run clear the suite's threshold? An empty run never passes.
    var meetsThreshold: Bool { total > 0 && passRate >= threshold }
}
