# Changelog

All notable changes to Coral are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

> The GitHub Release body is auto-generated from commits/PRs by the release
> workflow, and the in-app UpdateChecker shows that body. This file is the
> curated, human-facing history — keep the top `Unreleased` section current as
> you land changes, then move it under the new version number when you tag.

## [Unreleased]

## [1.0.0] — First public release
First Developer ID (non-App-Store) build, signed + notarized and distributed as
a DMG via GitHub Releases.

### Added
- In-app update checker: notifies when a newer GitHub Release exists and links to
  the download (no auto-install yet — Sparkle/EdDSA is on the backlog).
- Always-glanceable Claude rate-limit indicator (5-hour utilization %) in the
  chat/Code header, the sidebar rail, and the Usage section.

### Notes
- Ships with **App Sandbox off** (the chat spawns provider CLIs as subprocesses),
  which is why the distribution path is Developer ID + notarization rather than
  the Mac App Store.
- The signed build omits Sign in with Apple / iCloud / CloudKit for now (see
  `docs/RELEASE.md`); cross-device sync is pending.

[Unreleased]: https://github.com/marcosnovo/StrategyForge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/marcosnovo/StrategyForge/releases/tag/v1.0.0
