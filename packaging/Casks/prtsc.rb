# Rendered by scripts/bump-cask.sh from packaging/Casks/prtsc.rb in Sheikh566/PrtSc
# (the release workflow commits it here). Edit the template, not this file.
cask "prtsc" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/Sheikh566/PrtSc/releases/download/v#{version}/PrtSc-#{version}.dmg"
  name "PrtSc"
  desc "GNOME Shell-style screenshot UI for the macOS menu bar"
  homepage "https://github.com/Sheikh566/PrtSc"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "PrtSc.app"

  # BEGIN UNSIGNED
  # This release is not notarized (no Apple Developer ID yet). Remove the quarantine flag so
  # Gatekeeper does not block the first launch. Dropped automatically once builds are notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/PrtSc.app"]
  end
  # END UNSIGNED

  zap trash: [
    "~/Library/Application Support/PrtSc",
    "~/Library/Caches/io.github.sheikh566.PrtSc",
    "~/Library/HTTPStorages/io.github.sheikh566.PrtSc",
    "~/Library/Preferences/io.github.sheikh566.PrtSc.plist",
    "~/Library/Saved Application State/io.github.sheikh566.PrtSc.savedState",
  ]
end
