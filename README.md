# Coral

A native macOS app (SwiftUI, macOS 14+) that is a **visual generator of multi-agent
configurations for Claude Code**.

> The app is branded **Coral**. The Xcode project, target and module are still named
> `StrategyForge` (renaming those is a separate step); the bundle identifier is
> unchanged so existing installs and iCloud data keep working.

Coral does **not** run agents and does **not** talk to any Anthropic API. What it
does: you pick a *strategy* (topology), assign a Claude model and instance count to each
role, choose a local repository folder, and the app **writes the Claude Code configuration
files** into that repo (`.claude/agents/*.md` and an orchestration `CLAUDE.md`).
Optionally, it launches Claude Code in that folder.

> This uses your normal Claude Code plan. It does **not** consume the Managed Agents API.

## How Claude Code multi-agent actually works (non-negotiable facts)

1. **The orchestrator's model = the main Claude Code session's model.** It is chosen at
   launch (`claude --model <id>`) or with `/model` — never as agent frontmatter. The app
   documents it in `CLAUDE.md` and in the generated launch command.
2. **Workers / secondary roles pin their model** in the subagent's YAML frontmatter
   (`model:`), alongside `name`, `description`, `tools`.
3. **Single level of delegation.** The orchestrator delegates to subagents; subagents do
   not delegate further nor talk to each other — they only report back. "Debate" /
   "consensus" topologies are modeled as the orchestrator mediating multiple rounds.
4. **`description` decides when Claude delegates.** It must be specific and action-oriented.
5. **File locations:** subagents in `<repo>/.claude/agents/`; `CLAUDE.md` at the repo root.
6. **`tools`** restricts what each subagent can touch; omitting it inherits all tools.

## How to use

1. **New configuration** (＋ in the sidebar).
2. **Pick a strategy** from the dropdown — one of the eleven templates below. Its
   description shows what it does.
3. **Edit the roles table:** assign a model per role (Fable's picker shows a safeguard
   tooltip), set instance counts, restrict each role's tools, and edit each subagent's
   system prompt and `description`. Validation is shown live.
4. **Choose the repository** folder (the local repo to configure).
5. **Preview** the exact files in the right panel (one tab per file) and copy the launch
   command.
6. **Generate files** (confirms before overwriting), or **Generate & open Terminal**
   (writes files, copies the launch command, and opens Terminal at the repo).
7. **Save configuration** to keep it in the sidebar.

### Where the files land

- Subagents → `<repo>/.claude/agents/<name>.md` (one file per instance; `worker-1.md`,
  `worker-2.md`, …). Each has YAML frontmatter (`name`, `description`, `tools?`, `model`)
  followed by the system prompt.
- Orchestration doc → `<repo>/CLAUDE.md`. Coral only touches the block between
  `<!-- CORAL:START -->` and `<!-- CORAL:END -->` — the rest of an existing
  CLAUDE.md is preserved. (Blocks written by earlier versions, marked
  `<!-- STRATEGYFORGE:START/END -->`, are still recognized and upgraded in place.)

### Launching Claude Code with the right orchestrator model

The orchestrator's model is **not** in any file — it is the main session's model, set at
launch. Coral generates the exact command, e.g.:

```
claude --model claude-fable-5
```

or, inside a running session: `/model claude-fable-5`. The command is also documented in
the generated `CLAUDE.md`.

> **This does NOT consume the Managed Agents API.** It uses your normal Claude Code plan —
> the app only writes local config files.

## Loops, Advisor, progress and Token Saver

Beyond team configs, Coral ships four self-improving-agent features:

- **Loops** (rail → Loops): visually build a work loop — turn-based, goal-based,
  time-based or proactive — with a verifiable "done when" goal, guardrails, a hard
  turn limit, an independent verifier subagent (the maker never grades its own
  work) and optional STATE.md memory. Coral writes `LOOP.md`, `STATE.md` (never
  overwritten once it exists), `.claude/agents/loop-verifier.md` and an executable
  `loop.sh` into the repo, and can **run goal loops locally**: work turn → verifier
  verdict (`VERDICT: PASS/FAIL`) → iterate until PASS or the brake.
- **Advisor** (rail → Advisor): paste the prompt you'd give an agent and a local,
  deterministic decision tree recommends the Claude model, team strategy, loop kind
  and effort — showing the decision path visually. One click creates a chat or a
  pre-filled loop; nothing is saved until you act.
- **Simple progress**: one visual language everywhere — iteration dots (green/red
  by verdict, pulsing current), an Act → Verify → Done stage strip and a PASS/
  STOPPED badge — used by the loop runner and the chat's task progress.
- **Token Saver**: a context-weight pill in the chat header (green/amber/red),
  at most one contextual tip at a time (summarize & restart, convert the PDF you
  just attached, point at the exact section, batch small asks, model overkill,
  new topic = new chat) with real one-click actions, and a curated habits guide
  in Usage.

## The eleven strategies

1. **Orchestrator + Workers (Fan-out)** — orchestrator (Fable 5) + N identical workers
   (Sonnet 5) working parallel slices.
2. **Executor + Advisor** — executor (Sonnet 5, main session) consults a read-only advisor
   (Fable 5) on demand.
3. **Scout → Act** — a scout explores unfamiliar material first, then the executor acts.
4. **Triage Router (by cost)** — routes each subtask to the cheapest capable model, escalating
   only when needed.
5. **Planner → Implementers → Reviewer** — plan, delegate to implementers, then a
   read-only reviewer.
6. **Root-cause Debugging** — reproduce, isolate and fix a failure methodically.
7. **Domain Specialists** — orchestrator routing to backend / frontend / tests / security /
   docs.
8. **Research Fan-out** — orchestrator + N read-only researchers (Haiku) exploring in
   parallel.
9. **Debate / Consensus (mediated)** — moderator collects arguments from N debaters and
   synthesizes; no lateral communication.
10. **Sparring** — a challenger stress-tests the executor's proposals.
11. **Solo (baseline)** — a single agent, no subagents.

## Build phases

- [x] **Phase 0 — Scaffolding.** Folder structure, `Constants.swift`, README.
- [x] **Phase 1 — Data model (Codable).** `ClaudeModel`, `AgentRole`, `Strategy`,
  validations.
- [x] **Phase 2 — Predefined strategies.** The 11 editable templates (`StrategyLibrary`).
- [x] **Phase 3 — Generators.** `AgentFileGenerator`, `ClaudeMdGenerator`,
  `LaunchCommandGenerator`, `StrategyWriter` + unit tests.
- [x] **Phase 4 — UI.** `NavigationSplitView` editor with live preview and actions.
- [x] **Phase 5 — Persistence & closeout.** JSON store in Application Support, settings,
  smoke test.

### Out of scope (prepared hooks only)

See `Generators/CostEstimationHooks.swift`:
- TokenIA cost estimation per strategy.
- Import / export of strategies as shareable packages.

## Project structure

```
Coral/
  Coral/            # app sources
    Constants.swift         # model catalog + Claude Code tool list (single source)
    Models/                 # data model (Phase 1)
    Generators/             # file generators (Phase 3)
    ViewModels/             # view models (Phase 4)
    Views/                  # SwiftUI views (Phase 4)
  CoralTests/       # unit tests (Testing framework)
  CoralUITests/     # UI tests
```

## Future direction — "AgentDeck" (not in scope here)

Coral targets **Claude Code** (config files, your normal plan, single-level
delegation, no backend). A separate, more powerful path is Anthropic's **Managed Agents
API** (Research Preview): a coordinator with its own model invokes agents with their own
models via the `multiagent` field + the `agent_toolset_*` tool, each in an isolated
thread with SSE monitoring. That requires a backend to hold the API key and approved
preview access — a separate project ("AgentDeck"), deliberately not mixed in here.
