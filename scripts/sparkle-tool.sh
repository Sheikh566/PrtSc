#!/usr/bin/env bash
# Print the path of a Sparkle command line tool (sign_update, generate_keys, generate_appcast).
#
# Usage: scripts/sparkle-tool.sh <tool>
#
# The tools ship in the Sparkle SPM binary artifact, which Xcode/xcodebuild downloads when
# it resolves packages. Search order:
#   1. $SPARKLE_BIN_DIR
#   2. <repo>/build/DerivedData  (what scripts/build-app.sh and CI use)
#   3. every ~/Library/Developer/Xcode/DerivedData/*
# Run `xcodebuild -resolvePackageDependencies -project PrtSc.xcodeproj` first if nothing is found.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

tool="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${SPARKLE_BIN_DIR:-}" && -x "$SPARKLE_BIN_DIR/$tool" ]]; then
  echo "$SPARKLE_BIN_DIR/$tool"
  exit 0
fi

roots=("${BUILD_DIR:-$repo_root/build}/DerivedData")
for d in "$HOME"/Library/Developer/Xcode/DerivedData/*/; do
  [[ -d "$d" ]] && roots+=("${d%/}")
done

for root in "${roots[@]}"; do
  candidate="$root/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool"
  if [[ -x "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
done

echo "error: Sparkle tool '$tool' not found. Resolve packages first or set SPARKLE_BIN_DIR." >&2
exit 1
