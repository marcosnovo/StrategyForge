---
name: "🔌 Provider request / adapter"
about: Suggest a new AI provider for Coral (or offer to build the adapter)
title: "[Provider] "
labels: ["provider"]
---

**Which provider / model?**
<!-- e.g. Kimi K3, GLM, Qwen Coder, DeepSeek, Grok, Mistral, a local runtime… -->

**Why it's a good fit for Coral**
<!-- Cost, context window, speed, vision, open weights, offline/local, EU-hosted… -->

**Integration path (if you know it)**
- [ ] Ships a real CLI you log into (subscription) — preferred
- [ ] Anthropic-compatible endpoint (could reuse the `claude` runner via base URL)
- [ ] OpenAI-compatible endpoint
- [ ] API-key only (weaker fit for Coral's "your own subscription" model)
- [ ] Not sure

**CLI / auth details**
<!-- Binary name, login command, any known headless quirks (inherited-key stripping,
     skip-git-repo-check, SSO, region/billing friction). -->

**Are you offering to build it?**
<!-- If yes, see CONTRIBUTING.md → "Add a provider". Happy to help scope it. -->
