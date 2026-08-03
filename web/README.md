# Coral landing page

A static site with **no build step and no dependencies** — the marketing/landing site for
Coral, in **English and Spanish**.

```
web/
  index.html        # English (canonical)
  es/index.html     # Spanish
  coral.css         # shared design system, ported from the app's own tokens
  coral.js          # theme toggle, copy button, sticky-header hairline
  favicon.svg       # the app icon (copy of Branding/AppIcon.svg)
  og.png            # 1200×630 social card
  og.source.html    # the card's source — re-render it instead of editing the PNG
```

## Why it looks like the app

`coral.css` is not a separate visual language. It ports the app's real tokens so the site
and the product read as one thing:

| Site token | Comes from |
|---|---|
| `--app-bg`, `--card-bg`, `--ink`, `--coral`, `--accent`, … | `DesignSystem.swift` → `DesignSystem.classic` (the app's default palette), both light and dark |
| `--s-xs … --s-3xl`, `--corner`, `--inner-corner` | `Theme.swift` → `Space` / `Theme.corner` |
| `--team-blue … --team-rose` | `Theme.swift` team spectrum — used **only** in the topology mock, exactly as the app does |
| `.btn.moon` | the app's primary button style |
| aurora backdrop + film grain | `Backdrop.auroraCoral` |

Light is the default (as in the app), dark follows the OS, and the header toggle mirrors
Settings → Appearance. **If you re-skin the app, re-port the palette here** — the two
drifting apart is the whole thing this section exists to prevent.

The hero "screenshot" is a hand-built HTML replica of the app shell (nav rail → chat list →
thread → activity panel), not an image: it stays sharp at any density, themes itself, and
costs one request. Replace it with a real capture once the demo video's frames exist.

## Before you announce it

Ordered, and all of it is a five-minute job:

1. **Pick the domain** and replace every `https://example.com` in `index.html` and
   `es/index.html` (`og:url`, `og:image`). Open Graph needs **absolute** URLs or the card
   won't render on X / Slack / Product Hunt. Also set the absolute values on
   `<link rel="canonical">` and the `hreflang` alternates if the host doesn't serve from
   the domain root.
2. **Check the card**: after deploying, paste the URL into
   [cards-dev.twitter.com/validator](https://cards-dev.twitter.com/validator) or just DM
   yourself the link.
3. **Confirm the download link** points at a release that actually exists —
   `/releases/latest` 404s on a repo with no releases.
4. **Publish the Homebrew tap** if you want the `brew install` line on the page to work —
   see [`../docs/HOMEBREW.md`](../docs/HOMEBREW.md). Until then the copy button hands
   people a command that fails.
5. **Verify the two hardware claims**, because they're the only numbers on the page not
   read straight from the source:
   - *"Universal binary — Apple Silicon and Intel"* is inferred from the project setting
     no `ARCHS` override (so Xcode archives `ARCHS_STANDARD`). Confirm on the built app:
     `lipo -archs /Applications/Coral.app/Contents/MacOS/Coral` should print
     `x86_64 arm64`. If it prints only `arm64`, change that table row.
   - *"macOS 26+"* comes from `MACOSX_DEPLOYMENT_TARGET = 26.0` in the pbxproj. Note that
     `README.md` still says macOS 14+ — one of the two is wrong, and the page follows the
     build setting because that's what actually decides whether the app launches.

The language switcher and footer links use absolute paths (`/` and `/es/`), so they work on
any host that serves the directory at the domain root — and **not** over `file://`. Preview
with a local server instead:

```bash
cd web && python3 -m http.server 8080   # → http://localhost:8080
```

## Deploy it

This directory is deliberately a plain static site so it deploys anywhere with zero config —
and so it **dogfoods Coral's own Ship feature**: open a chat bound to this repo, pick the
paperplane → *Deploy to Vercel / Netlify / Cloudflare*, confirm, and Coral runs the CLI in
this folder and hands back the live URL.

By hand, from `web/`:

```bash
vercel --yes --prod                # Vercel
netlify deploy --prod --dir .      # Netlify
wrangler pages deploy .            # Cloudflare Pages
```

All three publish a static directory with no build command.

## Regenerating the social card

`og.png` is generated from `og.source.html` so it stays editable:

```bash
# macOS
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --screenshot=og.png --window-size=1200,630 --hide-scrollbars \
  "file://$PWD/og.source.html"
```

Confirm the output is exactly 1200×630 and that nothing is clipped — some headless builds
report a shorter viewport than the window, which silently crops the bottom of the card.

## Copy

The headline is a **verb and an outcome** ("Run a team of AI agents on your Mac"), with
"yours, not rented" demoted to the second line. That ordering is deliberate: a stranger
parses the job first and the wedge second. "Free" is the first word of the hero badge for
the same reason.

Load-bearing sections, in the order a reader meets them — don't drop these in a rewrite:
the **tension** (why one agent isn't enough), the **colony**, **"won't the official app
just absorb this?"**, and the **node/edge cost lens** that turns "no markup" into a number.

> ⚠️ **The colony canvas names real models.** Its tips are the app's actual catalog
> (`AIProvider.models` + `Constants.pricing`) — Opus 4.8 · Sonnet 5 · Haiku 4.5 · Fable 5,
> GPT-5 · GPT-5 mini, Gemini 2.5 Pro · 2.5 Flash — and so does the hero mockup. **When the
> catalog changes, change `coral.js` and the mockup too.** A landing page that advertises a
> model the app can't assign is worse than one with no picture. Note `gpt-5-codex` is
> deliberately absent: it's API-only and errors on a ChatGPT subscription login.
