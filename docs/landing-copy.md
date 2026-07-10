# StrategyForge — Landing copy (A/B, weeks 1–2)

Three landing variants, one per hypothesis. Same product, same CTA target
(waitlist), different headline promise. Run them as an even A/B/C split; the
winner is decided on **waitlist conversion (≥8%)** and qualitative reasons in
the "why did you sign up?" field.

Shared elements across all three:

- **Sub-badge (top):** *Your subscription. No API keys. No backend.*
- **Primary CTA:** `Join the waitlist` → email field.
- **Secondary CTA:** `Watch the 60-sec demo` → the real demo-path video.
- **Trust line (footer):** *StrategyForge runs the CLIs you already pay for
  (Claude Code, Codex, Gemini) on your Mac. Your keys and code never leave it.*
- **Two demo videos** embedded: (1) "describe a task → team runs → mission
  report", (2) "share a team, someone imports it in one click".

---

## Variant A — H1 · Mission Control for multi-agent dev

**Headline:** See exactly what your AI agents did — and what it cost.

**Sub-headline:** StrategyForge turns a run into a live timeline: every agent,
every step, tokens and dollars per turn. Stop flying blind through multi-agent
work.

**Body bullets:**
- **A live timeline of the whole team** — who did what, in order, in real time.
- **Cost & tokens per turn**, not a monthly surprise.
- **A shareable Mission Report** at the end: *"A 4-agent team finished for $0.83."*
- Works over your own Claude Code plan — no API keys.

**CTA:** `Get Mission Control` → waitlist.

**Who it's for:** developers already running Claude Code / multi-agent setups who
can't see or control what's happening.

---

## Variant B — H2 · The App Store for AI teams

**Headline:** Steal the best AI team setups. Share yours.

**Sub-headline:** A team of agents — models, roles, prompts — is a file you can
copy in one click. Import a proven setup, tweak it, run it on your own plan.

**Body bullets:**
- **One-click share & import** — a whole agent team as a link/file, not a blog post.
- **Start from a proven strategy** instead of a blank page.
- **Drag your repo** and StrategyForge shows your current `.claude/` setup as an
  editable team.
- Runs on your subscription — no keys, no backend.

**CTA:** `Browse the team library` → waitlist.

**Who it's for:** prosumers and teams who want great agent setups without building
them from scratch.

---

## Variant C — H3 · The cross-provider orchestrator

**Headline:** One team. GPT, Gemini and Claude — together.

**Sub-headline:** Let a GPT orchestrator delegate to Gemini workers and a Claude
advisor, on your own subscriptions. No single vendor CLI can do this. StrategyForge
does.

**Body bullets:**
- **Mix providers per role** — the right model for each job, one run.
- **Your plans, not API keys** — it drives the CLIs you already pay for.
- **Plan → delegate → synthesize**, orchestrated by the app itself.
- See the whole run and its cost in one place.

**CTA:** `Build a cross-provider team` → waitlist.

**Who it's for:** power users who juggle multiple AI subscriptions and want them
working as one team.

---

## Measurement (weeks 1–2)

- **Primary:** waitlist conversion per variant (target ≥8%; ≥100 signups total).
- **Secondary:** demo-video completion rate; which CTA is clicked.
- **Qualitative:** one required field on signup — *"What made you sign up?"* — to
  learn which promise landed.
- **Decision (week 6, after beta cohorts):** if *sharing* out-pulls the chat →
  double down on the marketplace (B); if the *timeline/cost* wins → Mission
  Control Pro (A). C is the moat regardless — keep it in every variant's body.

## Notes for build

Everything each variant promises already exists in the app and is demo-able today
(Claude path): the live timeline + per-turn cost (AgentActivityPanel), the Mission
Report (export .md/PNG), one-click team share/import (StrategyPackage text + file),
drag-your-repo (ClaudeConfigParser), and the cross-provider MetaOrchestrator
(verified end-to-end once Codex/Gemini CLIs are installed).
