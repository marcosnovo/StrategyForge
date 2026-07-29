# Installing Coral via Homebrew

Goal: `brew install --cask coral`. The cask itself lives in this repo at
[`Casks/coral.rb`](../Casks/coral.rb) as the source of truth, but Homebrew serves
casks from a **tap** (a repo named `homebrew-<name>`). This is a one-time setup you
do; after that each release is a two-line bump.

## One-time: create the tap

1. Create a public GitHub repo named **`homebrew-coral`** under your account
   (`marcosnovo/homebrew-coral`). The `homebrew-` prefix is required.
2. Add a `Casks/` folder and copy [`Casks/coral.rb`](../Casks/coral.rb) into it.
3. Commit and push.

Users can then run:

```bash
brew tap marcosnovo/coral
brew install --cask coral
# or in one line:
brew install --cask marcosnovo/coral/coral
```

## Every release: bump version + checksum

The release workflow builds `Coral-<version>.dmg` and attaches it to the
`v<version>` GitHub Release (see [`RELEASE.md`](RELEASE.md)). After it publishes:

```bash
V=1.2.3   # the version you just tagged
curl -L -o /tmp/Coral.dmg \
  "https://github.com/marcosnovo/StrategyForge/releases/download/v$V/Coral-$V.dmg"
shasum -a 256 /tmp/Coral.dmg
```

In `homebrew-coral/Casks/coral.rb`, set `version` to `$V` and paste the new
`sha256`. Commit and push — `brew upgrade --cask coral` now picks it up. Keep the
copy in this repo (`Casks/coral.rb`) in sync so it stays the source of truth.

## Validate the cask before publishing

```bash
brew audit --cask --new coral
brew style Casks/coral.rb
```

> Note: the placeholder `sha256` (all zeros) in the repo copy is intentional — it's
> filled per release. `brew audit` will flag it until a real release exists.

## Why a cask (not a formula)

Coral is a GUI macOS app shipped as a signed, notarized `.dmg` outside the Mac App
Store — that's exactly what a **cask** is for. Gatekeeper trusts the Developer ID
signature, so `brew install --cask coral` installs it with no "unidentified
developer" prompt.
