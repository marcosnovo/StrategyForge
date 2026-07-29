# Coral landing page

A single self-contained static page (`index.html`, no build step, no dependencies)
— the marketing/landing site for Coral. Inline CSS, system font stack, dark theme
with the coral/reef palette.

## Deploy it

This directory is deliberately a plain static site so it deploys anywhere with zero
config — and so it **dogfoods Coral's own "Deploy" (Ship) feature**: open a chat bound
to this repo, pick the paperplane → *Deploy to Vercel/Netlify/Cloudflare*, confirm, and
Coral runs the CLI in this folder and hands back the live URL.

By hand, from `web/`:

```bash
# Vercel
vercel --yes --prod

# Netlify
netlify deploy --prod --dir .

# Cloudflare Pages
wrangler pages deploy .
```

All three publish a static directory with no build command. The CTA buttons point at
the GitHub releases page and the repo; update them if the canonical download moves.

> Copy hypotheses and the A/B plan live in [`../docs/landing-copy.md`](../docs/landing-copy.md).
> This page leads with the **"yours, not rented"** wedge (no metering · your keys, your
> Mac · mix providers · verifier + provenance · native · open source) — the positioning
> that separates Coral from metered, account-gated cloud agents.
