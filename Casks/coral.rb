# Homebrew cask for Coral.
#
# This lives in the app repo as the source of truth; to actually serve
# `brew install --cask coral`, copy it into a tap repo named
# `homebrew-coral` (see docs/HOMEBREW.md). On each release, bump `version`
# and `sha256` — the release workflow builds `Coral-<version>.dmg` and
# attaches it to the `v<version>` GitHub Release, which is what `url` points at.
#
# To compute the checksum after a release:
#   curl -L -o Coral.dmg https://github.com/marcosnovo/StrategyForge/releases/download/v<version>/Coral-<version>.dmg
#   shasum -a 256 Coral.dmg
cask "coral" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # replace on release

  url "https://github.com/marcosnovo/StrategyForge/releases/download/v#{version}/Coral-#{version}.dmg",
      verified: "github.com/marcosnovo/StrategyForge/"
  name "Coral"
  desc "Native macOS app to design and run multi-agent AI teams on your own CLI plans"
  homepage "https://github.com/marcosnovo/StrategyForge"

  # Coral notifies about its own updates (in-app UpdateChecker reads GitHub Releases),
  # so let `brew livecheck` track the latest published tag too.
  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma" # macOS 14+

  app "Coral.app"

  zap trash: [
    "~/Library/Application Support/Coral",
    "~/Library/Preferences/com.marcosnovo.StrategyForge.plist",
    "~/Library/Caches/com.marcosnovo.StrategyForge",
  ]
end
