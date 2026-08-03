# Coral

**Open source (MIT) · native macOS (SwiftUI, macOS 14+).** Design *and* run multi-agent
AI teams — **on your own AI plans, locally.**

Coral is chat-first: you talk to a *team* of agents (an orchestrator plus specialized
subagents) instead of a single assistant, and it drives the CLIs you already pay for —
**Claude Code, Codex (ChatGPT), and Gemini** — headlessly on your own machine. It does
**not** resell tokens, hold your API keys, or route your prompts through a server: the
agents run against your own subscriptions on your own hardware.

> The app is branded **Coral**. The Swift module is `Coral`; the Xcode *project/target*
> are still named `StrategyForge` (a cosmetic rename left for later). The bundle id is
> unchanged so existing installs and iCloud data keep working.

## Why Coral is different

**One line:** the only **native macOS** app that orchestrates a **multi-agent team** with an
**independent verifier** — and **per-line, per-model provenance** — running entirely on **your own
CLI subscriptions**. No competitor combines all of these (verified across the 2026 landscape).

- **Native, not Electron.** Real SwiftUI — even the AI labs ship Electron shells for this workflow.
  Lower memory, instant launch, a Mac app that actually feels like a Mac app.
- **Your spend stays flat (BYO).** Coral drives the CLIs you already pay for — **Claude Code, Codex,
  and Gemini/`agy`** — headlessly. It never resells tokens, holds your keys, or routes prompts
  through a server: your bill is your provider's bill, with no markup.
- **Reviewer ≠ author.** An **independent verifier** gates autonomous loops, and can review an
  isolated worktree diff before you merge — ideally via a *different* provider family. It's the
  "leash" for agents: autonomous, but accountable.
- **Accountable by construction.** **Per-line provenance** attributes each line to the model that
  wrote it, even across providers.
- **Understands your code.** The **Map** turns a repo into an *interactive, agent-injected* code
  knowledge graph with estimated token savings — visual and portable to your own CLI, not a hosted
  vector index.
- **Compare & choose.** The **Arena** pits models/teams head-to-head with an independent judge and
  recommends one for the task — natively, on your CLIs.
- **Isolation per agent, enforced.** Each role gets a sandbox: its own git worktree, a hard
  read-only seat (the generated `tools:` grant is clamped, not merely asked for), or the shared
  tree. Parallel writers can't overwrite each other, and a verifier physically can't edit.
- **You can see where the money goes.** The **node/edge cost lens** prices a team as the graph it
  compiles to — paid nodes (model calls) against free edges (data carried in code) — next to what
  the straight-line version would have cost.
- **MIT, open, free.**

Honest gaps: there's no built-in deploy/host pipeline (by design — it's a pro-dev tool on your repo),
and Coral ships outside the Mac App Store (Developer ID + notarization), so first launch uses the
normal Gatekeeper allow.

### "Won't the first-party app just absorb this?"

The fair objection, and worth answering plainly: Claude Code already runs parallel sessions and
Agent Teams, and every lab is shipping an orchestrator. Three things a single-vendor product
**structurally cannot** do, which is why Coral is built the way it is:

1. **A vendor won't route your work to a rival.** Cross-provider delegation *inside one run* — a
   Claude orchestrator, a Codex implementer, a Gemini reviewer — means handing work and spend to a
   competitor. No lab ships that. Coral is provider-agnostic by construction, so the mix is the
   default rather than a concession.
2. **A same-family reviewer isn't an independent one.** A verifier drawn from the model that wrote
   the code agrees with itself in a different font. Coral's defaults to a *different provider
   family*, runs read-only on a fresh context, and grades against a real signal — a test that
   actually passed — not against the author's claim of doneness.
3. **Open beats a bundled feature.** MIT, no account, no server, no telemetry backend. You can read
   exactly what Coral does with your credentials, fork it, or take the generated `.claude/` config
   and leave. The exit is part of the product.

And on terms of service: Coral never carries your subscription tokens into a third-party client. It
invokes each provider's **official CLI with your own login** — the sanctioned path — which is
precisely what makes "your plan, no markup" possible.

## What it does

- **Chat with a team.** Pick a *strategy* (a team topology) or let the on-device Advisor
  recommend one from your prompt, then run it. The orchestrator plans, delegates to
  subagents, and synthesizes — you watch it happen in a live activity panel.
- **Mix real AIs per role** (Level 2). A single team can put a Claude orchestrator, a
  GPT-5 Codex coder, and a Gemini reviewer together — cross-provider delegation no single
  vendor CLI does, because each only delegates to its own models.
- **Run autonomous loops.** Build a work loop (turn / goal / time / proactive) with a
  verifiable "done when", a hard turn/spend brake, and an **independent verifier subagent
  that the maker never grades** — it iterates until PASS or the brake. Optional STATE.md
  memory carries context between runs; optional git-worktree isolation runs each loop on
  its own branch and merges back only on a verified PASS.
- **Code mode.** For a chat bound to a git repo: a changed-files list with per-file +/−,
  an inline diff, and git actions — stage, commit, branch, push, one-tap **Commit + PR**,
  and opt-in **Auto-PR** when a run finishes. A one-tap **Review** runs an independent
  read-only agent over the working diff and surfaces bugs/regressions (by severity) before
  you commit — reviewer ≠ author, applied to code.
- **Generate the config files.** Coral can also just write the Claude Code configuration
  (`.claude/agents/*.md` + an orchestration `CLAUDE.md`) into a repo, so a team you
  designed here runs in a plain `claude` session too. A team with teammates also gets a
  runnable **dynamic workflow** (`.claude/workflows/<team>.mjs`) — the team's topology as
  a program Claude Code executes (plan → parallel work → synthesize), giving the design a
  deterministic runtime, not just turn-by-turn delegation.
- **Remember across projects.** A knowledge base of learnings (patterns, decisions,
  pitfalls) at **two levels** — *yours* and *your team's*. Team learnings read as policy:
  they're injected ahead of personal ones, marked `[team]` in the generated `CLAUDE.md`,
  and a tight digest drops a preference before it drops a convention. Every entry carries
  real provenance; nothing is stored that an agent merely asserted.
- **See the graph you're paying for.** The **node/edge cost lens** (in the cost popover)
  splits a team into paid nodes and free edges, shows how wide the fan-out actually is,
  and compares it against the straight-line version of the same work. It's also the
  standing audit that generated workflows really parallelize — a role you set to 3
  instances emits 3 concurrent branches, and a test asserts it.
- **Sync** your teams/config across Macs via CloudKit (device-local transcripts stay
  local); **Usage** shows real token usage and your Claude plan headroom.

## How multi-agent works here (the non-negotiable facts)

1. **The orchestrator's model is the main session's model** — chosen at launch
   (`claude --model <id>` / `/model`), never as agent frontmatter. It's documented in the
   generated `CLAUDE.md` and launch command.
2. **Subagents pin their model** in YAML frontmatter (`model:`), alongside `name`,
   `description`, `tools`.
3. **Single level of delegation.** The orchestrator delegates to subagents; subagents
   report back — they don't delegate further or talk to each other. "Debate"/"consensus"
   is modeled as the orchestrator mediating rounds.
4. **`description` decides when Claude delegates** — it must be specific and
   action-oriented.
5. **Files:** subagents in `<repo>/.claude/agents/`; `CLAUDE.md` at the repo root (Coral
   only owns the block between `<!-- CORAL:START -->` and `<!-- CORAL:END -->`; the rest
   is preserved, and legacy `STRATEGYFORGE` blocks are upgraded in place).
6. **`tools`** restricts what a subagent can touch; omit to inherit all tools.
7. **Sandbox is per role.** *Automatic* follows the role kind (advisory seats read,
   producers get their own git worktree); *Isolated worktree*, *Read-only* and *Shared
   working tree* override it. Read-only is enforced by clamping the generated `tools:`
   grant — including the empty "inherit everything" grant — not by asking nicely in the
   prompt.

The verifier that grades a loop runs **read-only** (it can read + run tests, never edit),
so an independent judge can't "fix" the code it's judging.

## The 13 strategy templates

Fan-out (orchestrator + N workers) · Executor + Advisor · Scout → Act · Triage Router
(by cost) · Planner → Implementers → Reviewer · Explore → Plan → Build → Review ·
Root-cause Debugging · Domain Specialists (backend/frontend/tests/security/docs) ·
Research Fan-out · Debate / Consensus (mediated) · Sparring · **Solo · Economy (Haiku)**
· Solo (baseline). All are editable, and cross-provider assignment respects each role's
cost band (an economy seat maps to another cheap model, never a frontier one) and keeps
the orchestrator off Gemini (it drives the plan/synthesis).

## Providers & install

Coral drives each provider's own CLI on your subscription login:
- **Claude** — Claude Code (`claude`).
- **ChatGPT** — Codex (`codex`). On a ChatGPT-account login the CLI can't pick a model,
  so Coral uses the account default; an API key re-enables model choice.
- **Gemini** — Gemini CLI (`gemini`), via your Google login (GCA) or an API key.

The app can **install** missing CLIs for you (Connect → Install) and sign you in without
leaving the app. Nothing is sent to Coral's servers; token counts come from each CLI's
local logs, and Claude's plan % from your Claude Code login. Crash and hang diagnostics
(via MetricKit) are summarized into a local, exportable log and **stay on your Mac** —
there is no automatic upload and no analytics backend.

## Requirements & distribution

- macOS 14+ (Sonoma), Xcode to build.
- Ships **outside the Mac App Store** (App Sandbox is off — it spawns the provider CLIs),
  distributed as a Developer ID-signed, notarized DMG (see [`docs/RELEASE.md`](docs/RELEASE.md)).
- **Install:** download the DMG from [Releases](https://github.com/marcosnovo/StrategyForge/releases/latest),
  or via Homebrew once the tap is published — `brew install --cask marcosnovo/coral/coral`
  (see [`docs/HOMEBREW.md`](docs/HOMEBREW.md); the cask is [`Casks/coral.rb`](Casks/coral.rb)).

## Security & trust

Coral runs **sandbox-off**, drives the CLIs with **your own logins**, and can run shell
commands when you pick an autonomous mode — so its trust model is worth reading before you
run it. There's no server, no token reselling, and telemetry is off by default and local.
The whole point of open-sourcing it is that you can audit exactly what it does with your
credentials: see **[`SECURITY.md`](SECURITY.md)** for the trust model, what to audit
where, and how to report a vulnerability.

## Build & test

```
xcodebuild test -project StrategyForge.xcodeproj -scheme StrategyForge -destination 'platform=macOS'
```

Unit tests (`Testing` framework) are the automated gate; the shared scheme skips the
UITests target. See [`CLAUDE.md`](CLAUDE.md) for the loop-verifier gate and the
sensitive-files policy, and [`docs/BACKLOG.md`](docs/BACKLOG.md) for the prioritized
roadmap.

## Project structure

```
StrategyForge.xcodeproj
StrategyForge/               # app sources (Swift module: Coral)
  Constants.swift            # model catalog + tool list (single source)
  Models/                    # data model
  Generators/                # .claude / CLAUDE.md / loop.sh generators
  Services/                  # runners (ClaudeRunner, ProviderRun, MetaOrchestrator),
                             #   loops, git, usage, sync, keychain
  ViewModels/                # AppModel, ChatViewModel
  Views/                     # SwiftUI (chat, loops, code mode, advisor, usage)
StrategyForgeTests/          # unit tests
StrategyForgeUITests/        # UI tests
docs/                        # RELEASE.md, BACKLOG.md, reviews
```

## Contributing

Contributions are welcome — especially **new providers** (there's a "Coming soon · vote"
roadmap in the app; Kimi, GLM, Qwen and friends are waiting for adapters). See
**[`CONTRIBUTING.md`](CONTRIBUTING.md)** for first-build setup (signing team, bundle id,
optional Google/CloudKit config), the test gate, code style, the loop-engine guardrail,
and a step-by-step for adding a provider.

## License

[MIT](LICENSE) © 2026 Marcos Novo. The license covers the source; the **Coral** name and
logo are trademarks — don't use them to promote derived products without permission.
