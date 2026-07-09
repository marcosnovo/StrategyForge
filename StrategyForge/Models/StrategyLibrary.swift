//
//  StrategyLibrary.swift
//  StrategyForge
//
//  The seven predefined strategy templates. Every template is fully editable
//  (model and count per role). Each carries honest `orchestrationNotes` about
//  Claude Code's single-level delegation model.
//
//  Each accessor returns a FRESH value (new UUIDs) so editing one instance never
//  mutates the template or another instance.
//

import Foundation

/// Factory for the built-in strategy templates.
enum StrategyLibrary {

    /// All built-in templates, in presentation order.
    static var all: [Strategy] {
        [
            orchestratorWorkers(),
            executorAdvisor(),
            plannerImplementersReviewer(),
            domainSpecialists(),
            researchFanout(),
            debateConsensus(),
            sparring(),
            solo(),
        ]
    }

    // MARK: - Shared building blocks

    /// The orchestrator role. Its model is a *launch* setting (documented in
    /// CLAUDE.md and the launch command), never frontmatter — but we still store a
    /// suggested model so the launch command can be pre-filled.
    private static func orchestrator(
        name: String,
        model: ClaudeModel,
        description: String,
        systemPrompt: String
    ) -> AgentRole {
        AgentRole(
            name: name,
            role: .orchestrator,
            model: model,
            systemPrompt: systemPrompt,
            description: description,
            tools: [],            // inherits all; it is the main session
            count: 1,
            isOrchestrator: true
        )
    }

    // MARK: - 1. Orchestrator + Workers (Fan-out)

    static func orchestratorWorkers() -> Strategy {
        Strategy(
            name: "Orchestrator + Workers (Fan-out)",
            description: "One orchestrator plans and splits the task into parallel "
                + "slices; N identical workers each take a slice and report back.",
            roles: [
                orchestrator(
                    name: "orchestrator",
                    model: .fable5,
                    description: "Main session. Plans the work, splits it into "
                        + "independent slices, and delegates each to a worker.",
                    systemPrompt: """
                    You are the orchestrator of a fan-out team. Your job:
                    1. Understand the task and decompose it into independent slices \
                    that can proceed in parallel without stepping on each other.
                    2. Delegate each slice to a `worker` subagent with a precise, \
                    self-contained brief (files, scope, acceptance criteria).
                    3. Collect the workers' reports, integrate their work, resolve \
                    conflicts, and verify the whole.

                    Workers cannot see each other's work and cannot delegate. Give \
                    each one everything it needs up front.
                    """
                ),
                AgentRole(
                    name: "worker",
                    role: .worker,
                    model: .sonnet5,
                    systemPrompt: """
                    You are a worker. You receive one self-contained slice of a larger \
                    task from the orchestrator. Implement exactly that slice, keep your \
                    changes scoped to it, and report back a concise summary of what you \
                    did and anything the orchestrator needs to integrate it. Do not \
                    start unrelated work.

                    Do the simplest thing that works — no gold-plating: don't add \
                    features, refactors, abstractions, or error handling beyond what \
                    the slice requires.
                    """,
                    description: "Use to implement one independent slice of a "
                        + "parallelizable task. Invoke several in parallel for fan-out.",
                    tools: [],        // inherits all; workers implement code
                    count: 3,
                    isOrchestrator: false
                ),
            ],
            orchestrationNotes: """
            The orchestrator (main session) decomposes the task and delegates \
            independent slices to `worker` subagents, then integrates their results.

            Single level of delegation: workers do NOT talk to each other and do NOT \
            delegate further — they only report back to the orchestrator. Any \
            coordination between slices must be handled by the orchestrator, so make \
            each worker brief fully self-contained.
            """
        )
    }

    // MARK: - 2. Executor + Advisor

    static func executorAdvisor() -> Strategy {
        Strategy(
            name: "Executor + Advisor",
            description: "The executor (main session) does the work every turn and, "
                + "when it needs high-level guidance, consults a read-only advisor.",
            roles: [
                orchestrator(
                    name: "executor",
                    model: .sonnet5,
                    description: "Main session. Implements the work each turn and "
                        + "consults the advisor for high-level guidance when stuck.",
                    systemPrompt: """
                    You are the executor and the main session. You do the actual work \
                    each turn: read, plan, implement, and verify.

                    When you hit a genuinely high-level or ambiguous decision (design \
                    direction, trade-offs, risky refactor), delegate to the `advisor` \
                    subagent for guidance. The advisor does not write code — treat its \
                    output as advice and make the final call yourself.
                    """
                ),
                AgentRole(
                    name: "advisor",
                    role: .advisor,
                    model: .fable5,
                    systemPrompt: """
                    You are a high-level advisor. You are consulted on demand for \
                    difficult design decisions, trade-offs, and strategy. You do NOT \
                    write or edit code — you read what you need and return clear, \
                    reasoned recommendations with the trade-offs spelled out. Be \
                    concise and decisive.
                    """,
                    description: "Use on demand for high-level design advice, "
                        + "trade-off analysis, or when a decision is ambiguous. "
                        + "Advice only — does not write code.",
                    tools: Constants.readOnlyTools,
                    count: 1,
                    isOrchestrator: false
                ),
            ],
            orchestrationNotes: """
            The executor is the main session and performs all work. It invokes the \
            `advisor` subagent on demand for high-level guidance.

            The advisor is read-only and never writes code; the executor owns every \
            final decision. Single level of delegation: the advisor cannot delegate \
            and does not communicate with any other agent.
            """
        )
    }

    // MARK: - 3. Planner → Implementers → Reviewer

    static func plannerImplementersReviewer() -> Strategy {
        Strategy(
            name: "Planner → Implementers → Reviewer",
            description: "The orchestrator plans, delegates implementation to N "
                + "implementers, then invokes a read-only reviewer on the result.",
            roles: [
                orchestrator(
                    name: "orchestrator",
                    model: .fable5,
                    description: "Main session. Plans the work, delegates to "
                        + "implementers, then routes the result to the reviewer.",
                    systemPrompt: """
                    You are the orchestrator. First produce a clear implementation \
                    plan broken into independent units of work. Delegate each unit to \
                    an `implementer` subagent. After implementation, delegate a review \
                    of the changes to the `reviewer` subagent, then address its \
                    findings (yourself or via implementers) and verify.
                    """
                ),
                AgentRole(
                    name: "implementer",
                    role: .worker,
                    model: .sonnet5,
                    systemPrompt: """
                    You are an implementer. You receive one unit of a plan from the \
                    orchestrator and implement it fully and correctly, scoped to that \
                    unit. Report what you changed and any follow-ups the orchestrator \
                    should know about. Do the simplest thing that works — no \
                    gold-plating or changes beyond the unit.
                    """,
                    description: "Use to implement one planned unit of work. Invoke "
                        + "several in parallel when units are independent.",
                    tools: [],
                    count: 2,
                    isOrchestrator: false
                ),
                AgentRole(
                    name: "reviewer",
                    role: .reviewer,
                    model: .haiku45,
                    systemPrompt: """
                    You are a read-only, fresh-context verifier. You are invoked AFTER \
                    code has been implemented and you did not see the plan or write the \
                    code. Judge only the spec and the diff in front of you: does it \
                    meet every requirement? Work outside the spec's scope is a fail; \
                    deleted or weakened tests are a fail. The author's confidence is \
                    not evidence. Return a prioritized list of findings with file/line \
                    references; do not edit code.
                    """,
                    description: "Use right after implementing code to review the "
                        + "changes for correctness and bugs. Read-only.",
                    tools: Constants.readOnlyTools,
                    count: 1,
                    isOrchestrator: false
                ),
            ],
            orchestrationNotes: """
            Flow: the orchestrator plans → delegates units to `implementer` subagents \
            → invokes the read-only `reviewer` on the result → addresses findings.

            Single level of delegation: implementers and the reviewer report only to \
            the orchestrator and never to each other. The orchestrator is responsible \
            for feeding review findings back into implementation.
            """
        )
    }

    // MARK: - 4. Domain Specialists

    static func domainSpecialists() -> Strategy {
        Strategy(
            name: "Domain Specialists",
            description: "The orchestrator routes work to fixed domain experts: "
                + "backend, frontend, tests, security, docs.",
            roles: [
                orchestrator(
                    name: "orchestrator",
                    model: .fable5,
                    description: "Main session. Routes each piece of work to the "
                        + "appropriate domain specialist and integrates results.",
                    systemPrompt: """
                    You are the orchestrator of a team of domain specialists. Classify \
                    each piece of work by domain and delegate it to the matching \
                    specialist (`backend`, `frontend`, `tests`, `security`, `docs`). \
                    Integrate their outputs and resolve cross-domain concerns yourself.
                    """
                ),
                AgentRole(
                    name: "backend",
                    role: .specialist,
                    model: .sonnet5,
                    systemPrompt: "You are the backend specialist: APIs, data models, "
                        + "services, and server-side logic. Implement backend work "
                        + "cleanly and report integration points to the orchestrator.",
                    description: "Use for backend work: APIs, data models, services, "
                        + "server-side logic and persistence.",
                    tools: [],
                    count: 1
                ),
                AgentRole(
                    name: "frontend",
                    role: .specialist,
                    model: .sonnet5,
                    systemPrompt: "You are the frontend specialist: UI, views, and "
                        + "client-side behavior. Implement frontend work and report "
                        + "any backend contracts you depend on to the orchestrator.",
                    description: "Use for frontend work: UI, views, layout, and "
                        + "client-side behavior.",
                    tools: [],
                    count: 1
                ),
                AgentRole(
                    name: "tests",
                    role: .specialist,
                    model: .sonnet5,
                    systemPrompt: "You are the testing specialist. Write and maintain "
                        + "unit/UI tests for the work at hand and report coverage gaps "
                        + "to the orchestrator.",
                    description: "Use to write or update tests for implemented work "
                        + "and to identify coverage gaps.",
                    tools: [],
                    count: 1
                ),
                AgentRole(
                    name: "security",
                    role: .reviewer,
                    model: .sonnet5,
                    systemPrompt: "You are the security specialist. Review changes for "
                        + "vulnerabilities, unsafe input handling, and secret leakage. "
                        + "Read-only: report findings, do not edit code.",
                    description: "Use to review changes for security issues: unsafe "
                        + "input handling, secrets, and vulnerabilities. Read-only.",
                    tools: Constants.readOnlyTools,
                    count: 1
                ),
                AgentRole(
                    name: "docs",
                    role: .specialist,
                    model: .haiku45,
                    systemPrompt: "You are the documentation specialist. Write and "
                        + "update docs, READMEs, and inline documentation for the work, "
                        + "keeping them accurate and concise.",
                    description: "Use to write or update documentation and READMEs "
                        + "for implemented work.",
                    tools: ["Read", "Grep", "Glob", "Write", "Edit"],
                    count: 1
                ),
            ],
            orchestrationNotes: """
            The orchestrator classifies work by domain and delegates to fixed \
            specialists (`backend`, `frontend`, `tests`, `security`, `docs`).

            Single level of delegation: specialists never call each other. \
            Cross-domain dependencies (e.g. a frontend feature needing a backend \
            endpoint) are coordinated by the orchestrator, which passes the needed \
            context into each specialist's brief.
            """
        )
    }

    // MARK: - 5. Research Fan-out

    static func researchFanout() -> Strategy {
        Strategy(
            name: "Research Fan-out",
            description: "The orchestrator dispatches N read-only researchers to "
                + "explore different areas of the codebase in parallel and summarize.",
            roles: [
                orchestrator(
                    name: "orchestrator",
                    model: .fable5,
                    description: "Main session. Splits a research question into areas "
                        + "and dispatches a researcher per area, then synthesizes.",
                    systemPrompt: """
                    You are the orchestrator of a research fan-out. Break the question \
                    into distinct areas of the codebase or problem space, and dispatch \
                    one `researcher` per area with a precise scope. Collect their \
                    summaries and synthesize a single coherent answer, noting gaps and \
                    contradictions.
                    """
                ),
                AgentRole(
                    name: "researcher",
                    role: .researcher,
                    model: .haiku45,
                    systemPrompt: """
                    You are a read-only researcher. You are given one area to explore. \
                    Read the relevant code/docs, and return a concise, well-organized \
                    summary of your findings with file references. You do not modify \
                    anything and you do not explore outside your assigned area.
                    """,
                    description: "Use to explore one area of the codebase and return a "
                        + "summary. Invoke several in parallel to cover more ground. "
                        + "Read-only.",
                    tools: Constants.readOnlyTools,
                    count: 3,
                    isOrchestrator: false
                ),
            ],
            orchestrationNotes: """
            The orchestrator partitions a research question into areas and dispatches \
            a read-only `researcher` per area in parallel, then synthesizes the \
            summaries.

            Single level of delegation: researchers do not coordinate with each other; \
            each is blind to the others' findings. The orchestrator is responsible for \
            merging results and spotting gaps or overlaps.
            """
        )
    }

    // MARK: - 6. Debate / Consensus (mediated)

    static func debateConsensus() -> Strategy {
        Strategy(
            name: "Debate / Consensus (mediated)",
            description: "A moderator orchestrator collects arguments from N agents "
                + "holding different positions and synthesizes a consensus over rounds.",
            roles: [
                orchestrator(
                    name: "moderator",
                    model: .opus48,
                    description: "Main session. Poses the question to each debater, "
                        + "collects their arguments, and synthesizes a consensus.",
                    systemPrompt: """
                    You are the moderator of a mediated debate. For each round:
                    1. Pose the question (and, in later rounds, a summary of the \
                    previous round's arguments) to each `debater` subagent.
                    2. Collect their independent arguments.
                    3. Synthesize: identify agreements, tensions, and the strongest \
                    reasoning, then either run another round or declare a consensus.

                    You are the ONLY channel between debaters — they never talk to each \
                    other. Any "response" a debater gives to another position is really \
                    a response to the summary you passed them.
                    """
                ),
                AgentRole(
                    name: "debater",
                    role: .advisor,
                    model: .sonnet5,
                    systemPrompt: """
                    You are a debater. The moderator gives you a question and, in later \
                    rounds, a summary of other positions. Argue your assigned position \
                    (or the most defensible position you can construct) with clear \
                    reasoning and evidence. Return only your argument to the moderator. \
                    You do not talk to other debaters and you do not modify code.
                    """,
                    description: "Use to argue a distinct position on a decision. "
                        + "Invoke several with different stances; the moderator "
                        + "mediates. Advice only.",
                    tools: Constants.readOnlyTools,
                    count: 3,
                    isOrchestrator: false
                ),
            ],
            orchestrationNotes: """
            IMPORTANT — this is NOT lateral communication. Claude Code allows a single \
            level of delegation, so debaters never talk to each other. The `moderator` \
            (main session) is the only channel: it passes each debater the question and \
            a summary of the other positions, collects their arguments, and synthesizes \
            the consensus across multiple rounds.

            Model each "rebuttal" as the moderator handing a debater a summary of the \
            opposing arguments and asking for a response. The moderator owns synthesis \
            and the final decision.
            """
        )
    }

    // MARK: - 7. Sparring (builder vs breaker)

    static func sparring() -> Strategy {
        Strategy(
            name: "Sparring (builder vs breaker)",
            description: "A builder implements; an adversarial breaker writes failing "
                + "tests to expose weaknesses. The orchestrator mediates and decides "
                + "over rounds until the code holds.",
            roles: [
                orchestrator(
                    name: "orchestrator",
                    model: .fable5,
                    description: "Main session. Assigns work to the builder and the "
                        + "breaker, weighs their outputs, and resolves disputes.",
                    systemPrompt: """
                    You mediate a builder and an adversarial breaker to harden the \
                    code. Each round: ask the `builder` to implement (or to fix the \
                    breaker's failing test by changing the CODE), then ask the \
                    `breaker` to probe the result for weaknesses. Weigh both and \
                    decide when the code holds or when to stop.

                    The builder and breaker never talk to each other — you are the \
                    only channel. Resolve any dispute yourself; never let a test be \
                    weakened to force a pass.
                    """
                ),
                AgentRole(
                    name: "builder",
                    role: .worker,
                    model: .sonnet5,
                    systemPrompt: """
                    You are the builder. Implement the task correctly and simply (no \
                    gold-plating). When the breaker's test fails, fix the CODE to make \
                    it pass — never weaken, edit, or delete a test. Report what you \
                    changed.
                    """,
                    description: "Use to implement the task and to fix the failures the "
                        + "breaker exposes.",
                    tools: [],
                    count: 1
                ),
                AgentRole(
                    name: "breaker",
                    role: .specialist,
                    model: .sonnet5,
                    systemPrompt: """
                    You are the adversarial breaker. Read the builder's latest changes \
                    and write ONE failing test that exposes a real weakness — an edge \
                    case, a missing boundary check, or a broken invariant. Do not fix \
                    anything and do not touch other tests. If the code is genuinely \
                    solid, say so and write nothing.
                    """,
                    description: "Use after the builder makes changes to probe for "
                        + "weaknesses with a single failing test.",
                    tools: [],
                    count: 1
                ),
            ],
            orchestrationNotes: """
            The orchestrator relays between a `builder` (implements) and a `breaker` \
            (writes a failing test to expose weaknesses), running rounds until the \
            code holds.

            Single level of delegation: the builder and breaker never communicate \
            with each other — the orchestrator passes each the other's output and \
            owns the final decision. The breaker never weakens or deletes tests; \
            disputes are resolved by the orchestrator.
            """
        )
    }

    // MARK: - 8. Solo (baseline)

    static func solo() -> Strategy {
        Strategy(
            name: "Solo (baseline)",
            description: "A single agent with no subagents — a baseline to compare "
                + "cost and quality against multi-agent strategies.",
            roles: [
                orchestrator(
                    name: "solo",
                    model: .opus48,
                    description: "Main session. Does all the work directly with no "
                        + "subagents.",
                    systemPrompt: """
                    You are working solo. There are no subagents to delegate to — read, \
                    plan, implement, and verify everything yourself. This configuration \
                    exists as a baseline to compare cost and quality against \
                    multi-agent strategies.
                    """
                ),
            ],
            orchestrationNotes: """
            Baseline: a single agent (the main session) does everything directly. No \
            subagents are generated, so there is no delegation at all. Use this to \
            compare cost and quality against the multi-agent strategies.
            """
        )
    }
}
