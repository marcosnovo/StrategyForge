//
//  AgentSandboxTests.swift
//  StrategyForgeTests
//
//  Per-AGENT isolation (Conductor doesn't have it; Factory's validators do). The point of
//  these tests is that the sandbox is ENFORCED rather than requested: a read-only seat has
//  its generated `tools:` grant clamped, and an isolated seat gets `isolation: 'worktree'`
//  on its workflow node. Plus the compatibility guarantee: `.auto` — the default and what
//  every already-saved team decodes to — must generate byte-identical files.
//

import Testing
import Foundation
@testable import Coral

struct AgentSandboxTests {

    private func role(_ kind: RoleKind, sandbox: AgentSandbox = .auto,
                      tools: [String] = []) -> AgentRole {
        AgentRole(name: "seat", role: kind, model: .sonnet5,
                  systemPrompt: "Do the thing.", description: "Does the thing.",
                  tools: tools, sandbox: sandbox)
    }

    // MARK: - The policy itself

    @Test func autoReproducesTheRoleKindDefaults() {
        // The pre-field behaviour, unchanged: producers isolate, advisory seats read.
        for kind in RoleKind.allCases {
            #expect(AgentSandbox.auto.isolatesInWorktree(for: kind) == !kind.isReadOnlyByDefault)
            #expect(AgentSandbox.auto.isReadOnly(for: kind) == kind.isReadOnlyByDefault)
        }
    }

    @Test func explicitChoicesOverrideTheRoleKind() {
        // A reviewer forced into a worktree can edit; a worker forced read-only cannot.
        #expect(AgentSandbox.worktree.isolatesInWorktree(for: .reviewer))
        #expect(!AgentSandbox.worktree.isReadOnly(for: .reviewer))
        #expect(AgentSandbox.readOnly.isReadOnly(for: .worker))
        #expect(!AgentSandbox.readOnly.isolatesInWorktree(for: .worker))
        // Opting out is a real opt-out: no isolation, no read-only clamp.
        #expect(!AgentSandbox.shared.isolatesInWorktree(for: .worker))
        #expect(!AgentSandbox.shared.isReadOnly(for: .worker))
    }

    // MARK: - Enforcement in the generated agent file

    @Test func aReadOnlySeatCannotInheritEveryTool() {
        // An empty `tools` grant means "inherit ALL" — which for a read-only seat would be
        // the exact opposite of the promise. It must become the read-only set instead.
        let md = AgentFileGenerator.markdown(for: role(.worker, sandbox: .readOnly), instanceName: "seat")
        #expect(md.contains("tools: \(Constants.readOnlyTools.joined(separator: ", "))"))
        #expect(!md.contains("Edit"))
        #expect(!md.contains("Write"))
    }

    @Test func aReadOnlySeatIntersectsAnExplicitGrantAndNeverWidensIt() {
        let granted = ["Read", "Edit", "Bash", "Grep"]
        let md = AgentFileGenerator.markdown(for: role(.worker, sandbox: .readOnly, tools: granted),
                                             instanceName: "seat")
        #expect(md.contains("tools: Read, Grep"))
        #expect(!md.contains("Edit"))
        #expect(!md.contains("Bash"))
    }

    @Test func autoLeavesTheGrantExactlyAsTheTemplateWroteIt() {
        // The compatibility guarantee: an untouched team generates what it always did,
        // even for an advisory role whose kind reads as read-only.
        let granted = ["Read", "Edit", "Bash"]
        let auto = AgentFileGenerator.markdown(for: role(.reviewer, sandbox: .auto, tools: granted),
                                               instanceName: "seat")
        #expect(auto.contains("tools: Read, Edit, Bash"))
        let shared = AgentFileGenerator.markdown(for: role(.worker, sandbox: .shared, tools: granted),
                                                 instanceName: "seat")
        #expect(shared.contains("tools: Read, Edit, Bash"))
    }

    // MARK: - Enforcement in the generated workflow

    @Test func theWorkflowIsolatesExactlyTheSeatsThatAskedForIt() {
        var s = StrategyLibrary.domainSpecialists()
        // Specialists edit → isolated under .auto.
        #expect(WorkflowGenerator.workflow(for: s)!.contains("isolation: 'worktree'"))

        // Opt every producer out and the isolation disappears from the emitted graph.
        for i in s.roles.indices where !s.roles[i].isOrchestrator {
            s.roles[i].sandbox = .shared
        }
        #expect(!WorkflowGenerator.workflow(for: s)!.contains("isolation: 'worktree'"))

        // Force them back in explicitly and it returns.
        for i in s.roles.indices where !s.roles[i].isOrchestrator {
            s.roles[i].sandbox = .worktree
        }
        #expect(WorkflowGenerator.workflow(for: s)!.contains("isolation: 'worktree'"))
    }

    @Test func aReadOnlySeatCarriesItsClampedGrantIntoTheWorkflowToo() {
        // The hole a review caught: clamping `tools:` in .claude/agents/<name>.md does
        // nothing if the same team runs through .claude/workflows/<team>.mjs, where the
        // node would otherwise inherit every tool. Read-only nodes are pinned to their
        // generated agent file, so both execution paths enforce the same grant.
        var s = StrategyLibrary.domainSpecialists()
        let reviewerIndex = s.roles.firstIndex { $0.role == .reviewer }!
        let reviewerName = s.roles[reviewerIndex].name
        s.roles[reviewerIndex].sandbox = .readOnly

        let js = WorkflowGenerator.workflow(for: s)!
        #expect(js.contains("agentType: '\(reviewerName)'"))
        // …and the file that agentType resolves to really is the clamped one.
        let file = AgentFileGenerator.generate(for: s)
            .first { $0.relativePath == ".claude/agents/\(reviewerName).md" }!
        #expect(file.contents.contains("tools: \(Constants.readOnlyTools.joined(separator: ", "))"))
    }

    @Test func nonReadOnlySeatsAreNotPinnedSoUntouchedTeamsEmitWhatTheyAlwaysDid() {
        // .auto must not start pinning agent types — that would change the emitted
        // workflow for every existing team, including advisory roles whose ROLE KIND
        // reads as read-only but whose grant was never clamped.
        for strategy in StrategyLibrary.all where !strategy.subagentRoles.isEmpty {
            #expect(!WorkflowGenerator.workflow(for: strategy)!.contains("agentType:"),
                    "\(strategy.name) pinned an agentType without an explicit read-only seat")
        }
    }

    @Test func theExpandedInstanceNameIsTheOneTheAgentFileUses() {
        // With count > 1 the files are <name>-1.md … <name>-N.md, so the pin has to
        // carry the suffix or agentType resolves to nothing.
        var role = role(.worker, sandbox: .readOnly)
        role.count = 3
        #expect(WorkflowGenerator.agentTypeOption(for: role, instance: 2) == ", agentType: 'seat-2'")
        role.count = 1
        #expect(WorkflowGenerator.agentTypeOption(for: role, instance: 1) == ", agentType: 'seat'")
        role.sandbox = .auto
        #expect(WorkflowGenerator.agentTypeOption(for: role, instance: 1).isEmpty)
    }

    @Test func aReadOnlySeatIsNeverGivenAWorktree() {
        var s = StrategyLibrary.domainSpecialists()
        for i in s.roles.indices where !s.roles[i].isOrchestrator {
            s.roles[i].sandbox = .readOnly
        }
        #expect(!WorkflowGenerator.workflow(for: s)!.contains("isolation: 'worktree'"))
    }

    // MARK: - Persistence

    @Test func theSandboxSurvivesARoundTripAndOldDataDecodesToAuto() throws {
        let original = role(.worker, sandbox: .worktree, tools: ["Read"])
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(AgentRole.self, from: data)
        #expect(back.sandbox == .worktree)

        // A role saved before the field existed, and one saved by a NEWER build with a
        // sandbox this version doesn't know: both land on .auto instead of throwing and
        // taking the user's whole team with them.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "sandbox")
        let legacy = try JSONDecoder().decode(
            AgentRole.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.sandbox == .auto)

        json["sandbox"] = "gvisor-from-the-future"
        let future = try JSONDecoder().decode(
            AgentRole.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(future.sandbox == .auto)
    }
}
