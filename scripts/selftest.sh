#!/usr/bin/env bash
# Offline checks for the release scripts (appcast + cask rendering, dmg layout).
#
# Usage: scripts/selftest.sh
# Runs in CI and locally; needs no secrets or network. Uses a dummy .app, not a real build.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- appcast -----------------------------------------------------------------------------
appcast="$tmp/appcast.xml"
sig="aGVsbG8gd29ybGQ="
"$here/update-appcast.sh" --appcast "$appcast" --version 0.1.0 --build 3 \
  --url "https://example.com/PrtSc-0.1.0.dmg?a=1&b=2" --signature "$sig" --length 12345 \
  --date "Wed, 18 Nov 2026 10:00:00 +0000" >/dev/null
"$here/update-appcast.sh" --appcast "$appcast" --version 0.2.0 --build 9 \
  --url "https://example.com/PrtSc-0.2.0.dmg" --signature "$sig" --length 23456 >/dev/null
"$here/update-appcast.sh" --appcast "$appcast" --version 0.2.0 --build 10 \
  --url "https://example.com/PrtSc-0.2.0.dmg" --signature "$sig" --length 23457 >/dev/null

[[ "$(grep -c '<item>' "$appcast")" == 2 ]] || fail "expected 2 items (re-run must replace)"
first="$(grep -n 'shortVersionString' "$appcast" | head -n 1)"
[[ "$first" == *0.2.0* ]] || fail "newest item should come first"
grep -q 'sparkle:minimumSystemVersion>26.0<' "$appcast" || fail "minimumSystemVersion missing"
grep -q 'sparkle:edSignature="aGVsbG8gd29ybGQ="' "$appcast" || fail "signature missing"
grep -q '<sparkle:version>10</sparkle:version>' "$appcast" || fail "replaced item should have build 10"
! grep -q '<sparkle:version>9</sparkle:version>' "$appcast" || fail "old item not removed"
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$appcast"; fi
"$here/update-appcast.sh" --appcast "$appcast" --version "1 2" --build 1 --url u --signature "$sig" --length 1 \
  2>/dev/null && fail "bad version should be rejected"

# --- cask --------------------------------------------------------------------------------
sha="$(printf 'x' | shasum -a 256 | awk '{ print $1 }')"
"$here/bump-cask.sh" --version 1.2.3 --sha256 "$sha" --out "$tmp/signed.rb" >/dev/null
grep -q 'version "1.2.3"' "$tmp/signed.rb" || fail "cask version"
grep -q "sha256 \"$sha\"" "$tmp/signed.rb" || fail "cask sha"
! grep -q 'quarantine' "$tmp/signed.rb" || fail "signed cask must not strip quarantine"
"$here/bump-cask.sh" --version 1.2.3 --sha256 "$sha" --out "$tmp/unsigned.rb" --unsigned >/dev/null
grep -q 'quarantine' "$tmp/unsigned.rb" || fail "unsigned cask should strip quarantine"
! grep -q '__' "$tmp/unsigned.rb" || fail "placeholder left in cask"

# --- dmg ---------------------------------------------------------------------------------
if command -v hdiutil >/dev/null 2>&1; then
  mkdir -p "$tmp/Dummy.app/Contents/MacOS"
  printf '#!/bin/sh\n' > "$tmp/Dummy.app/Contents/MacOS/Dummy"
  chmod +x "$tmp/Dummy.app/Contents/MacOS/Dummy"
  "$here/make-dmg.sh" "$tmp/Dummy.app" "$tmp/test.dmg" Dummy >/dev/null
  mnt="$tmp/mnt"
  mkdir "$mnt"
  hdiutil attach "$tmp/test.dmg" -mountpoint "$mnt" -nobrowse -readonly -quiet
  ok=1
  [[ -d "$mnt/Dummy.app" ]] || ok=0
  [[ -L "$mnt/Applications" ]] || ok=0
  hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet
  [[ $ok == 1 ]] || fail "dmg should contain the app and an Applications symlink"
fi

echo "selftest OK"
