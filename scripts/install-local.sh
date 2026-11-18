#!/usr/bin/env bash
# Build a Release PrtSc.app, sign it, install it to /Applications and relaunch it.
#
# Usage: scripts/install-local.sh [identity]
#   identity  codesign identity to use. Default: "PrtSc Local Signing" if that identity is in
#             your keychain, otherwise "-" (ad-hoc).
#
# Why a local identity: macOS ties the Screen Recording permission to the app's designated
# requirement. For an ad-hoc build that is the build's cdhash, so every reinstall loses the
# permission. With a self-signed certificate it's the certificate, so the permission survives.
#
# Environment:
#   BUILD_DIR  scratch directory for DerivedData and the archive (default: a temp dir)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_identity="PrtSc Local Signing"

if [[ $# -gt 1 ]]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

if [[ $# -eq 1 ]]; then
  identity="$1"
elif security find-identity -p codesigning | grep -q "\"$local_identity\""; then
  identity="$local_identity"
else
  identity="-"
  echo "warning: '$local_identity' not found; signing ad-hoc (Screen Recording must be re-granted after each install)" >&2
fi

work="${BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/prtsc-install.XXXXXX")}"
out="$work/out"
version="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$repo_root/PrtSc.xcodeproj/project.pbxproj" | head -1)"
build="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' "$repo_root/PrtSc.xcodeproj/project.pbxproj" | head -1)"

BUILD_DIR="$work/build" "$repo_root/scripts/build-app.sh" "${version:-0.0.0}" "${build:-1}" "$out"
"$repo_root/scripts/sign-app.sh" "$out/PrtSc.app" "$identity"

if pgrep -f "/Applications/PrtSc.app/Contents/MacOS/PrtSc" >/dev/null; then
  osascript -e 'tell application id "io.github.sheikh566.PrtSc" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -f "/Applications/PrtSc.app/Contents/MacOS/PrtSc" >/dev/null || break
    sleep 0.1
  done
  pkill -f "/Applications/PrtSc.app/Contents/MacOS/PrtSc" 2>/dev/null || true
fi

rm -rf /Applications/PrtSc.app
ditto "$out/PrtSc.app" /Applications/PrtSc.app
codesign --verify --deep --strict /Applications/PrtSc.app
open /Applications/PrtSc.app

[[ -n "${BUILD_DIR:-}" ]] || rm -rf "$work"
echo "Installed /Applications/PrtSc.app ($version, build $build), signed with '$identity'"
