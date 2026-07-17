# Releasing Coral — step by step

The `.github/workflows/release.yml` workflow does the whole pipeline (build →
sign → notarize → DMG → GitHub Release) when you push a version tag. But it
needs a few one-time secrets that only you can create (they involve your Apple
Developer account). Here's exactly what to do, in order.

## 0. What you need
- An **Apple Developer Program** membership ($99/yr) — required for the
  "Developer ID Application" certificate and notarization.
- Your **Team ID** (10 chars, e.g. `ABCDE12345`): appears at
  <https://developer.apple.com/account> → Membership.

## 1. Create the signing certificate (once)
1. On your Mac, open **Keychain Access** (or Xcode → Settings → Accounts →
   Manage Certificates).
2. Create a **"Developer ID Application"** certificate (Xcode: the `+` →
   "Developer ID Application"). This is the cert Gatekeeper trusts for apps
   distributed OUTSIDE the App Store.
3. Export it **with its private key**: in Keychain Access, select the cert +
   its key → right-click → "Export 2 items…" → save as `DeveloperID.p12`, set
   an export password (remember it).
4. Base64-encode it for the secret:
   ```
   base64 -i DeveloperID.p12 | pbcopy
   ```

## 2. Create the notarization API key (once)
1. Go to <https://appstoreconnect.apple.com/access/integrations/api> →
   **Team Keys** → generate a key with the **"Developer"** role.
2. Download the `AuthKey_XXXXXX.p8` (you can only download it once).
3. Note the **Key ID** (on that page) and the **Issuer ID** (top of the page).
4. Base64-encode the key:
   ```
   base64 -i AuthKey_XXXXXX.p8 | pbcopy
   ```

## 3. Add the six repo secrets (once)
GitHub → your repo → **Settings → Secrets and variables → Actions → New
repository secret**. Add exactly these names:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | the base64 from step 1.4 |
| `DEVELOPER_ID_CERT_PASSWORD` | the .p12 export password from step 1.3 |
| `DEVELOPMENT_TEAM` | your 10-char Team ID |
| `NOTARY_KEY_ID` | Key ID from step 2.3 |
| `NOTARY_ISSUER_ID` | Issuer ID from step 2.3 |
| `NOTARY_KEY_P8_BASE64` | the base64 from step 2.4 |

## 4. Dry-run it once (recommended before trusting it)
1. GitHub → **Actions → release → Run workflow** (workflow_dispatch), enter a
   version like `0.0.1-test`.
2. Watch the logs. The slow step is **notarization** (`notarytool … --wait`) —
   it can take several minutes; that's normal.
3. It creates a **draft** Release with the DMG attached. Download the DMG,
   open it on a Mac that has never seen the app, and confirm Gatekeeper opens
   it without the "unidentified developer" warning. Then delete the test
   Release + tag.

## 5. Real releases
- Bump nothing by hand — the **tag drives the version**.
- Tag and push:
  ```
  git tag v1.0.0
  git push origin v1.0.0
  ```
- The workflow builds `Coral-1.0.0.dmg`, notarizes+staples it, and opens a
  **draft** Release named "Coral 1.0.0". Review the auto-generated notes, then
  click **Publish**.
- The in-app **UpdateChecker** reads the latest *published* Release, so users
  get the update prompt only once you publish (not on the draft).

## Notes / gotchas
- The runner image is `macos-26` (the project's deployment target is macOS
  26.5). If that image isn't available on your account, either lower the
  deployment target or point `runs-on` at a self-hosted Mac.
- The app ships **outside the Mac App Store** (App Sandbox is off — it spawns
  the provider CLIs), which is exactly why Developer ID + notarization is the
  distribution path.
- If a future release adds **auto-update signing** (Sparkle/EdDSA), add the
  signing step here and publish the public key with the app (backlog #60).
