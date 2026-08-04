//
//  WastedWorkTests.swift
//  StrategyForgeTests
//
//  The duplicated-work detector: the same tool + target run more than once (esp. by a second
//  agent) is the collaboration failure that's invisible in the answer and only shows in the
//  trajectory. Pure — no CLIs.
//

import Testing
import Foundation
@testable import Coral

struct WastedWorkTests {
    private func step(_ title: String, _ detail: String?, agent: String? = nil, delegation: Bool = false) -> ActivityStep {
        ActivityStep(title: title, detail: detail, at: .distantPast, isDelegation: delegation, agent: agent)
    }

    @Test func flagsSameToolAndTargetAcrossAgents() {
        let steps = [
            step("Read", "api/docs.md", agent: "researcher"),
            step("Bash", "npm test", agent: "researcher"),
            step("Read", "api/docs.md", agent: "writer"),   // writer redoes the researcher's read
        ]
        let dups = WastedWork.detect(steps)
        #expect(dups.count == 1)
        let d = try? #require(dups.first)
        #expect(d?.title == "Read")
        #expect(d?.detail == "api/docs.md")
        #expect(d?.count == 2)
        #expect(d?.crossAgent == true)           // two different agents did the same read
        #expect(WastedWork.redundantCount(dups) == 1)   // one redundant call
    }

    @Test func ignoresDelegationsRoleMarkersAndTargetlessSteps() {
        let steps = [
            step("researcher", "look into X", agent: nil, delegation: true),
            step("researcher", "look into X", agent: nil, delegation: true),   // repeated delegation, not "work"
            step("role.working", "task", agent: "researcher"),
            step("role.working", "task", agent: "writer"),
            step("TodoWrite", nil, agent: "researcher"),                       // no target → not comparable
            step("TodoWrite", nil, agent: "writer"),
        ]
        #expect(WastedWork.detect(steps).isEmpty)
    }

    @Test func oneAgentLoopingIsFlaggedButNotCrossAgent() {
        let steps = [
            step("WebFetch", "https://x.com", agent: "researcher"),
            step("WebFetch", "https://x.com", agent: "researcher"),
        ]
        let dups = WastedWork.detect(steps)
        #expect(dups.count == 1)
        #expect(dups.first?.crossAgent == false)   // same agent looping, not a handoff loss
        #expect(dups.first?.count == 2)
    }

    @Test func distinctWorkIsNotFlagged() {
        let steps = [
            step("Read", "a.swift", agent: "researcher"),
            step("Read", "b.swift", agent: "writer"),
        ]
        #expect(WastedWork.detect(steps).isEmpty)
    }
}
