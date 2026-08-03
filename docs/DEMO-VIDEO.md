# The 60-second demo

The competitive analysis lists this as a **P0**, alongside the website and the Homebrew
tap: the technical moat exists, but nothing carries it to a stranger in the first minute.
A landing page can claim "cross-provider team with an independent verifier". Only video
*shows* it, and showing it is the whole argument.

This is a shooting script, not a mood board. Follow it literally and it takes an afternoon.

---

## What the video has to prove

In order, and nothing else — every second not spent on these four is a second wasted:

1. **A team, not a chatbot.** Several named agents working at once, visibly.
2. **Different providers in the same run.** Claude, Codex and Gemini badges on one screen.
3. **The reviewer is not the author.** A verdict from a different provider family, gating
   the merge.
4. **It's your plan.** No account, no key, no meter — the cost pill shows *your* spend.

The wedge is **"yours, not rented"**. If a viewer can't repeat that sentence afterwards,
the cut failed regardless of how good it looked.

---

## Capture setup

| | |
|---|---|
| Tool | QuickTime *Screen Recording* (free, no watermark) or CleanShot X |
| Resolution | Record on a **1920×1080** display scale, export 1080p. Product Hunt's player is small — anything denser turns the UI to mush |
| Frame rate | 60 fps capture, 30 fps export |
| Window | Coral at roughly 1440×900, centred, on a plain desktop |
| Theme | **Light** — it's the app's default, it reads better in a small embedded player, and it distinguishes us from the sea of dark IDE demos |
| Audio | **None.** Ship with captions burned in; most Product Hunt and X views are muted |
| Cursor | Enable click highlighting. Move deliberately — no hunting |

**Before you hit record**

- Real repo, real task. A fabricated one shows, and one honest run is worth three staged ones.
- Sign into all three providers beforehand; the sign-in flow is a different video.
- Empty the chat list of anything you don't want a stranger reading. Check the window title.
- Hide the menu bar clock and any notification you'd have to edit out.
- Do the run once untimed. You are recording the *second* one.

---

## The shot list

Total 60s. Timings are targets; the beats matter more than the stopwatch.

### 0:00–0:05 — Cold open, no logo

Coral already open on an empty chat. The user types, in one take:

> `Make the payment webhook idempotent and prove it with tests.`

**Caption:** *One prompt. Not one agent.*

> No splash screen. No "introducing". The first frame is the product. A logo animation at
> second zero is the single most common way a launch video loses half its viewers.

### 0:05–0:14 — The team assembles

The Advisor picks the team; the topology appears in the activity panel. Hold on it long
enough to read the names and the **cost pill**.

**Caption:** *An orchestrator plus specialists — picked for the task, priced before it runs.*

### 0:14–0:26 — Three providers, one run

Agents start working in parallel. Hover so the provider badges are legible: **Opus 5**
orchestrating, **GPT-5 Codex** implementing, **Gemini 3 Pro** reviewing.

**Caption:** *Claude plans. Codex builds. Gemini reviews. Same run.*

> This is the shot no competitor can copy, so it gets the most time. Do not cut away early.

### 0:26–0:36 — The verifier gates it

The reviewer runs the suite on a fresh context. Land on the verdict: **PASS**, from a
different provider family.

**Caption:** *The reviewer isn't the author — and it runs read-only, so it can't "fix" what it's judging.*

### 0:36–0:46 — Provenance, then merge

Open the diff. Show the per-line provenance tint — this line came from Codex, that one
from Claude. Then merge from the isolated worktree.

**Caption:** *Every line attributed to the model that wrote it. Autonomous, but accountable.*

### 0:46–0:54 — The bill

Cut to the cost popover: paid nodes, free edges, and the spend against **your** plan's
headroom.

**Caption:** *No metering. No markup. Your plan, your Mac, your bill.*

### 0:54–1:00 — The card

Static end card, held for a full 4 seconds so it can be screenshotted:

```
Coral
Multi-agent AI teams — yours, not rented.
Native macOS · open source (MIT) · no account
<your-domain>
```

---

## Captions

Burn them in — Product Hunt, X and LinkedIn all autoplay muted, and an uncaptioned demo is
a silent movie about software.

- Bottom third, safe from the player's control bar.
- 34–40px, semibold, white on a 60%-black rounded plate.
- One line each. If a caption doesn't fit on one line, the caption is wrong, not the font size.
- Use the exact strings above. They're the landing page's copy, and repetition is the point.

---

## Deliverables

| File | Where | Notes |
|---|---|---|
| `coral-demo-60s.mp4` | Product Hunt gallery, X, landing page | H.264, 1080p30, **under 8 MB** if it's going inline on the page |
| `coral-demo-30s.mp4` | X / LinkedIn | Cut sections 3 and 5; keep the cold open and the verdict |
| `coral-demo.gif` | README | The 0:14–0:26 provider shot only, ≤5 MB, no captions |
| 5 stills | Product Hunt gallery | Team topology · three providers · PASS verdict · provenance diff · cost lens |

Product Hunt shows the **first gallery item** as the thumbnail. Make it the three-provider
shot, not the empty chat — a screenshot of an empty window is indistinguishable from every
other chat app on the site.

---

## Things that will tempt you, and shouldn't

- **A talking head.** Adds 20 seconds and proves nothing about the product.
- **Speeding up the run.** If it's slow, say so in the caption. A visibly fake 4× run
  undermines the one thing the video is for: showing that this actually works.
- **Feature-listing.** The Map, Arena, loops and Ship are all real and all cuttable. This
  video makes one argument. Make separate clips for the rest.
- **Showing an error you then fix.** Save it — it's a great *second* video, and a terrible
  first impression.
