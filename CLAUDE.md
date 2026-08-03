# StrategyForge (Coral) — agent notes

Native macOS app (SwiftUI, macOS 14+). See `README.md` for what the product
does and the non-negotiable facts about how Claude Code multi-agent works —
read that first, this file only covers running the loop verifier.

## Build & test (the loop's verifier gate)

    xcodebuild test -project StrategyForge.xcodeproj -scheme StrategyForge -destination 'platform=macOS'

The product was renamed to **Coral** (`PRODUCT_NAME = Coral`); the test
target's `TEST_HOST` in the pbxproj points at
`$(BUILT_PRODUCTS_DIR)/Coral.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Coral`, so
the plain command above works with no overrides. The module is also `Coral`
now, so tests `@testable import Coral` (not `StrategyForge`). 165 tests,
31 suites.

Targets: `StrategyForge` (app), `StrategyForgeTests` (unit tests — the real
gate for most changes, written with `Testing` / `@Test`, not XCTest),
`StrategyForgeUITests`. This command is the only automated check there is — and
since the repo went public, **CI runs exactly it** on every push to `main` and
every PR (`.github/workflows/tests.yml`, `macos-26`, ~3–5 min; docs/branding-only
pushes are skipped via `paths-ignore`). A change is not "done" until it passes —
never call something finished on the strength of a read-through alone.

That CI job is also the way a **Linux session** (remote/web Claude Code) gets the
gate run at all: it can't invoke `xcodebuild` locally, but pushing the branch and
opening a PR does run the real suite on a Mac runner. Push, then read the check
result — don't report unverified work as done when this path is available.

Requires macOS + Xcode. This suite cannot run in a Linux sandbox (e.g. a
remote/web Claude Code session) — say so explicitly rather than skipping the
gate silently, and prefer handing the run to a session on the user's Mac. The
`StrategyForge` scheme is shared (`StrategyForge.xcodeproj/xcshareddata/
xcschemes/StrategyForge.xcscheme`), so the command above resolves on a fresh
clone without anyone opening Xcode first to create a private one.

## Using /loop or /goal in this repo

- Point the verifier step at the `xcodebuild test` command above.
- Good fits: fixing a specific failing test, an isolated bug with a
  reproducible symptom, mechanical refactors bounded by the existing suite.
- Bad fits: anything touching the Loop feature's own data model
  (`Models/LoopPlan.swift`, `Services/LoopScheduler.swift`, `Services/
  LoopRunner.swift`, `Generators/LoopFileGenerator.swift`) without a human
  reading the diff — this code generates and schedules loops for other
  repos, so a subtle regression here is easy to miss with tests alone and
  expensive once it ships in a generated `loop.sh`.
- Keep `maxTurns` conservative (5–10) until you've seen a couple of runs
  behave — the app's own `LoopPlan` defaults to 20, which is generous for a
  first run on unfamiliar code.
