# Contributing to Coral

Thanks for wanting to help. Coral is a native macOS app (SwiftUI, macOS 14+) that
designs and runs multi-agent AI teams on your own AI subscriptions. This guide gets you
building, tells you where the guardrails are, and shows the single highest-value
contribution: **adding a new AI provider.**

## Prerequisites

- **macOS 14+ (Sonoma)** and **Xcode**. This is an Apple-platform app — it can't be
  built or tested on Linux.
- At least one provider CLI installed to actually run teams (`claude`, `codex`, or
  `gemini`) — the app can install them for you, or you can bring your own.

## First build (one-time local setup)

Clone, open `StrategyForge.xcodeproj`, and before your first build set a few things that
are intentionally **not** baked into the repo (they're personal to each developer):

1. **Signing team.** Signing & Capabilities → set **your own** Team. The committed
   `DEVELOPMENT_TEAM` is the maintainer's and won't sign for you. For local dev,
   "Sign to Run Locally" / automatic signing is fine.
2. **Bundle identifier.** Change `com.marcosnovo.StrategyForge` to your own if you sign
   with your team (or Xcode will complain about provisioning).
3. **Optional — Google sign-in.** `Constants.swift` ships a
   `YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com` placeholder; the feature stays
   disabled until you drop in your own OAuth client ID. Everything else works without it.
4. **Optional — CloudKit sync.** Sync uses the maintainer's iCloud container
   (`iCloud.com.marcosnovo.StrategyForge`), which only works under that account. The app
   runs fully **without** sync; to develop it, point the entitlement at your own
   container. Transcripts are always device-local either way.

None of the above blocks running the app or the test suite locally.

## The test gate

Unit tests (Swift `Testing` framework, not XCTest) are the automated gate. A change
isn't done until this passes:

```
xcodebuild test -project StrategyForge.xcodeproj -scheme StrategyForge -destination 'platform=macOS'
```

The shared `StrategyForge` scheme skips the UITests target, so this resolves on a fresh
clone. CI is currently **paused** (cost) — run the gate locally and say so in your PR.

## Code style

- SwiftUI + `@Observable @MainActor` view models. **No Combine** — prefer `async`/`await`.
- 4-space indentation; PascalCase types, camelCase members; `let` by default; avoid
  force-unwraps.
- Match the surrounding file's comment density and idiom. Comments explain *why*, not
  *what*.
- New list rows use the shared `CoralRow`; new user-facing strings go through `L10n`
  (English + Spanish) via `model.t(...)`.

## Guardrails (please respect these)

- **The loop engine needs a human diff review.** Changes to `Models/LoopPlan.swift`,
  `Services/LoopScheduler.swift`, `Services/LoopRunner.swift`, and
  `Generators/LoopFileGenerator.swift` generate and schedule autonomous loops for *other*
  people's repos — a subtle bug ships in a generated `loop.sh`. Tests alone aren't enough;
  a maintainer will read these diffs closely.
- **The multi-agent facts are non-negotiable** — see the "How multi-agent works here"
  section in `README.md` (single level of delegation, orchestrator model = session model,
  subagents pin their model, read-only verifier). Don't break these invariants.
- **Don't add an analytics backend or phone-home.** Telemetry stays local and opt-in.

## Highest-value contribution: add a provider 🎉

Coral has a **"Coming soon · vote"** roadmap in Connections (Kimi, GLM, Qwen, DeepSeek,
Grok, Mistral, local…). Turning a voted future provider into a real one is the most
useful PR you can send. The shape:

1. Add a case to **`Models/AIProvider.swift`** and fill in its metadata (displayName,
   `binaryName`, `tint`, `logoAsset`, `npmPackage`, `loginCommand`, `models`,
   `planOptions`). Most fits are a CLI you log into with a subscription — mirror the
   closest existing provider (Qwen ≈ Gemini's CLI shape; Kimi/GLM/DeepSeek ≈ an
   Anthropic-compatible base-URL that can reuse the `claude` runner).
2. Handle its **headless auth quirks** in the runner (`Services/ProviderRun.swift` /
   `Services/ClaudeRunner.swift`). Expect the same class of issues we've already hit:
   stripping inherited `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` so a base-URL provider
   doesn't 401, `--skip-git-repo-check`-style flags, and binary resolution.
3. Add localized connect help (`provider.<id>.connect`) and, if you have art, a brand
   logo asset.
4. **Verify against the real CLI** and add tests where the behavior is pure (command
   building, parsing). We won't merge a provider we can't see work end-to-end.
5. If it was on the "Coming soon" ballot, remove it from `Models/FutureProvider.swift`.

## Pull requests

- Branch from `main`, keep PRs focused, and describe what you changed and how you
  verified it (paste the test result).
- Make sure the gate passes locally. New behavior gets a test.
- By contributing you agree your work is licensed under the project's [MIT License](LICENSE).

Questions or a bigger idea? Open a discussion or a lightweight issue first — happy to
help scope it.
