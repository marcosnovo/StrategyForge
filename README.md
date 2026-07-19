# Coral

A native macOS app (SwiftUI, macOS 14+) to **design *and* run multi-agent AI teams —
on your own AI plans, locally.**

Coral is chat-first: you talk to a *team* of agents (an orchestrator plus specialized
subagents) instead of a single assistant, and it drives the CLIs you already pay for —
**Claude Code, Codex (ChatGPT), and Gemini** — headlessly on your own machine. It does
**not** resell tokens, hold your API keys, or route your prompts through a server: the
agents run against your own subscriptions on your own hardware.

> The app is branded **Coral**. The Swift module is `Coral`; the Xcode *project/target*
> are still named `StrategyForge` (a cosmetic rename left for later). The bundle id is
> unchanged so existing installs and iCloud data keep working.

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
  and opt-in **Auto-PR** when a run finishes.
- **Generate the config files.** Coral can also just write the Claude Code configuration
  (`.claude/agents/*.md` + an orchestration `CLAUDE.md`) into a repo, so a team you
  designed here runs in a plain `claude` session too.
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
local logs, and Claude's plan % from your Claude Code login.

## Requirements & distribution

- macOS 14+ (Sonoma), Xcode to build.
- Ships **outside the Mac App Store** (App Sandbox is off — it spawns the provider CLIs),
  distributed as a Developer ID-signed, notarized DMG (see [`docs/RELEASE.md`](docs/RELEASE.md)).

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
