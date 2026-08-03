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

The page leads with the **"yours, not rented"** wedge — no metering · your logins, your Mac ·
mix providers per role · reviewer ≠ author · per-line provenance · native, not Electron —
plus the two sections that answer the objections the competitive analysis flagged as our
weakest axis: **"won't the official app just absorb this?"** and the **node/edge cost lens**
that turns "no markup" into a number. Keep both when you rewrite; they're load-bearing.
