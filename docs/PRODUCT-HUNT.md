# Launching Coral on Product Hunt

**Question asked:** *what's missing if I want to ship this tomorrow as an open-source project?*

**Short answer:** the product is ready; the **launch surface** isn't. Nothing below is code.
Every blocker is an account, an artefact or a recording — six or seven hours of work, all of
which needs a Mac. The realistic call is **launch the day after tomorrow, not tomorrow**, and
the single reason is the demo video: it's the highest-leverage asset and the one you can't
rush.

---

## Blockers — a launch fails without these

| # | Blocker | Why it's fatal | Time |
|---|---|---|---|
| 1 | **There is no release to download.** The site's "Download for macOS" and the cask both point at `/releases/latest`, which 404s until you tag one. | The #1 comment on a launch with a broken download is "link's dead", and you don't get a second first impression. | 1–2 h (see [`RELEASE.md`](RELEASE.md)) |
| 2 | **The green test gate has not run on this branch.** These changes were written in a Linux session; `xcodebuild test` needs macOS. | You'd be shipping a DMG built from unverified code. | 15 min |
| 3 | **The site isn't deployed and has no domain.** `og:url` / `og:image` are still `https://example.com`. | Open Graph needs absolute URLs, so with a placeholder the X and Product Hunt cards render blank. | 30 min (see [`../web/README.md`](../web/README.md)) |
| 4 | **The Homebrew tap isn't published.** The landing page hands out a copy button for a command that fails. | Publish it, or delete the line before you announce. | 15 min (see [`HOMEBREW.md`](HOMEBREW.md)) |
| 5 | **No demo video.** | On Product Hunt the gallery *is* the pitch. Screenshots of a chat window are indistinguishable from every other chat app on the site — the multi-agent, multi-provider, verified run only exists if you show it moving. | half a day (see [`DEMO-VIDEO.md`](DEMO-VIDEO.md)) |
| 6 | **Notarization is unproven.** The pipeline is documented but has never been exercised end to end. | An un-notarized DMG throws "damaged and can't be opened" on a stranger's Mac. Not a Gatekeeper warning — a wall. | 1 h, and it must be tested on a **second Mac** |

**The dependency chain is fixed:** gate → release → notarize → tap → site → video. Every step
below the first is blocked by the one above it.

---

## Should-haves — they change the outcome, but a launch survives without them

- **A hunter, or self-hunt early.** Post at **00:01 PT**. The 24-hour clock is brutal and a
  09:00 post has already lost a third of its day.
- **Seed the first comment yourself** before anyone else arrives — the maker comment is the
  only long-form pitch anyone reads. Draft below.
- **A pinned "how it compares" comment.** Someone *will* ask about Conductor, Warp, Factory
  and Claude Code within the hour. Answer it first, generously, and name their strengths;
  [`COMPETITIVE-ANALYSIS-2026-07-23.md`](COMPETITIVE-ANALYSIS-2026-07-23.md) already has
  the material. Defensive answers lose threads.
- **Repo hygiene** — a stranger's second click after the site: repo description, topics
  (`macos`, `swiftui`, `ai-agents`, `claude-code`, `open-source`), the OG image, and a
  README that opens with the demo GIF. Cheap, and the first impression for developers.
- **Issue templates + a couple of `good first issue`s.** "Open source" that can't be
  contributed to reads as "source available".
- **Decide what you do with the traffic.** No newsletter, no waitlist, no analytics means a
  launch spike converts to nothing. A single "star the repo" ask is a legitimate answer —
  but pick one deliberately instead of by omission.

---

## Explicitly *not* blockers

Say no to these tomorrow:

- A website rewrite. It's done, bilingual, and matches the app.
- Any new feature. The 8.5/10 product is not what's holding the launch.
- Windows/Linux, a web version, a Mac App Store build.
- Pricing. It's MIT and BYO — "free, runs on your own plan" is the whole pitch.
- CI. Worth having; irrelevant to a launch day.

---

## Positioning on the day

**Tagline (60 char limit):**
> Multi-agent AI teams on your Mac, on your own AI plans

**Description (260 chars):**
> Coral is a native macOS app that designs and runs a team of AI agents — orchestrator plus
> specialists — driving the Claude Code, Codex and Gemini CLIs you already pay for. Independent
> verifier, per-line provenance, no metering, no account. Open source (MIT).

**Topics:** Developer Tools · Artificial Intelligence · Mac · Open Source · GitHub

**The one sentence to repeat all day:**
> The only native Mac orchestrator that runs a multi-agent team on *your* subscriptions, with a
> verifier from a *different* provider family — and it's MIT.

### Maker's first comment (draft)

> I kept hitting the same wall: one agent isn't enough for real work, but every tool that runs
> several of them wants a new account, a new API key, and a per-token bill on top of the three
> AI subscriptions I already pay for.
>
> Coral is my answer. It's a native Mac app (SwiftUI, not Electron) that designs *and* runs a
> team — an orchestrator plus specialists — by driving the CLIs you already have: Claude Code,
> Codex, Gemini. Your logins, your machine, your bill. Coral holds no keys and has no server.
>
> Two things I care about more than the multi-agent part:
>
> **The reviewer is never the author.** An independent verifier — by default from a *different*
> provider family — gates autonomous loops and grades the diff before you merge. It runs
> read-only, so it can't quietly fix what it's judging.
>
> **Every line is attributed** to the model that wrote it, even when providers took turns on the
> same file. Autonomous, but accountable.
>
> It's MIT. Not "source available" — actually MIT, no account, no telemetry backend. The app runs
> unsandboxed because it has to spawn the provider CLIs, which is exactly why the source is open:
> read SECURITY.md and check what it does with your credentials.
>
> Honest gaps, up front: macOS only, no hosted deploy pipeline (it drives your own deploy CLIs
> instead), and it ships outside the App Store. Happy to go deep on any of it — especially how it
> compares to Conductor, Warp, Factory or just using Claude Code directly.

### The comparison comment (post it before you're asked)

> Fair question, and the honest version: **Conductor** is the closest — also native Mac, also
> BYO-subscription. It's closed, Claude+Codex only, and its parallel sessions aren't a coordinated
> team with a verifier. **Warp** genuinely orchestrates all three CLIs, but meters you in credits
> and declined subscription login. **Factory** is more mature than Coral in most dimensions
> — real validator agents, two-level memory, a strong code graph — but it's API-key-only, so a
> Claude Max or ChatGPT subscription doesn't work, and it bills per token. **Claude Code itself**
> is excellent and Coral runs on top of it; the thing it can't do is delegate to a rival's model
> or review its own work with one.
>
> Where I'd tell you *not* to use Coral: you're not on a Mac, you want a hosted deploy pipeline,
> or you only ever need one agent — in which case just use the CLI directly.

---

## Timeline that actually works

**Today (Mac).** Run the gate. Cut and notarize the release, install the DMG on a second Mac.
Publish the tap. Buy the domain, deploy the site, fix the absolute URLs, check the OG card.

**Tomorrow (morning).** Record the demo. Cut the 60s and 30s versions and the README GIF.
Take the five gallery stills. Repo hygiene.

**Tomorrow (evening).** Stage the Product Hunt draft: gallery ordered with the three-provider
shot first, both comments written and ready to paste.

**Day after, 00:01 PT.** Ship. Then stay in the thread all day — on Product Hunt, replying is
worth more than anything you could have built instead.
