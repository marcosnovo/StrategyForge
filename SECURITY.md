# Security & trust

Coral is a local-first developer tool, and its trust model is unusual enough to
state plainly. **Read this before you run it — and audit the code, that's why it's
open source.**

## What Coral does on your machine

- **Runs without the App Sandbox.** The app spawns the provider CLIs (`claude`,
  `codex`, `gemini`) as subprocesses, which the macOS App Sandbox forbids — so Coral
  ships sandbox-off, distributed as a Developer ID-signed, notarized build (not via
  the Mac App Store).
- **Uses *your* logins.** It drives the CLIs you already signed into with your own
  subscriptions. It does **not** hold your provider API keys, resell tokens, or route
  your prompts through any server. The one optional key (an OpenAI API key, only if
  you enable it) is stored in the **macOS Keychain**, never on disk or in the synced
  config.
- **Can run shell commands when you choose to.** Chat autonomy is opt-in per chat:
  `plan` (read-only) → `acceptEdits` (auto-applies file edits) → `full`
  (`bypassPermissions` — edits + shell). The autonomy you pick is passed straight to
  the CLI's `--permission-mode`; Coral adds no hidden escalation.
- **Talks to exactly these hosts:** your provider CLIs' own endpoints (via the CLIs),
  `api.github.com` (release-update check + optional `gh` actions), and Google/Apple
  OAuth endpoints **only if** you use those sign-ins. There is no analytics backend.
- **Telemetry is off by default and local.** When you opt in (Settings), a handful of
  funnel events are appended to a JSONL file in Application Support — nothing is
  uploaded. Turn it off and you can delete the file from the same screen.
- **Supply-chain guard.** CLI installs can be pinned to a vetted version per release
  (`AIProvider.pinnedCLIVersions`) instead of resolving `@latest`.

## Where to look when auditing

| Concern | Start here |
|---|---|
| How CLIs are spawned & what flags are passed | `Services/ClaudeRunner.swift`, `Services/ProviderRun.swift`, `Generators/LaunchCommandGenerator.swift` |
| Autonomy → permission mode mapping | `Models/AppSettings.swift` (`ChatAutonomy`) |
| Secret storage | `Services/KeychainStore.swift` |
| OAuth (Apple / Google sign-in) | `Services/AuthService.swift` |
| What syncs via CloudKit | `Services/ConfigSyncStore.swift`, `Models/PortableConfiguration.swift` |
| Local telemetry (opt-in) | `Services/Analytics.swift` |
| Network calls | `Services/UpdateChecker.swift`, `Services/HTTPCache.swift` |

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Email
**marcosnovo@gmail.com** with details and, if you can, a reproduction. You'll get an
acknowledgement within a few days. Coordinated disclosure is appreciated — give a
reasonable window for a fix before publishing.

## Supported versions

This is a young project; only the latest `main` (and the most recent released build)
receives security fixes.
