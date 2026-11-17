#!/usr/bin/env bash
# Select the newest installed Xcode whose major version matches $1 (default 27).
#
# Usage: scripts/select-xcode.sh [major]
#
# On GitHub runners Xcode lives in /Applications/Xcode_<version>.app. Locally this is
# usually a no-op: if the active Xcode already has the requested major version nothing
# is changed. Uses sudo for xcode-select only when it has to switch.
set -euo pipefail

major="${1:-27}"

active_major() {
  xcodebuild -version 2>/dev/null | awk '/^Xcode / { split($2, v, "."); print v[1]; exit }'
}

if [[ "$(active_major || true)" == "$major" ]]; then
  echo "Active Xcode already has major version $major:"
  xcodebuild -version
  exit 0
fi

# Newest first; version sort handles Xcode_27.10 vs Xcode_27.2.
candidate=""
while IFS= read -r app; do
  candidate="$app"
  break
done < <(find /Applications -maxdepth 1 \( -name "Xcode_${major}*.app" -o -name "Xcode-${major}*.app" \) 2>/dev/null | sort -rV)

if [[ -z "$candidate" ]]; then
  echo "error: no Xcode $major found in /Applications (runner image too old?)" >&2
  find /Applications -maxdepth 1 -iname '*xcode*' >&2 || true
  exit 1
fi

echo "Selecting $candidate"
sudo xcode-select -s "$candidate/Contents/Developer"
xcodebuild -version
