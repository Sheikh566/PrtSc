#!/usr/bin/env bash
# Build a compressed disk image containing PrtSc.app and an /Applications symlink.
#
# Usage: scripts/make-dmg.sh <path/to/PrtSc.app> <output.dmg> [volume-name]
#   volume-name defaults to "PrtSc".
#
# Uses only hdiutil/ditto. The output file is replaced if it already exists. Sign or
# notarize the result afterwards if needed (codesign --sign ... <dmg>, scripts/notarize.sh).
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

app="$1"
out="$2"
volname="${3:-PrtSc}"

[[ -d "$app" && "$app" == *.app ]] || { echo "error: $app is not an .app bundle" >&2; exit 66; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"

mkdir -p "$(dirname "$out")"
rm -f "$out"

# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
attempt=1
until hdiutil create -volname "$volname" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null; do
  if [[ $attempt -ge 3 ]]; then
    echo "error: hdiutil create failed after $attempt attempts" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  echo "hdiutil failed, retrying ($attempt/3)..." >&2
  sleep 5
done

hdiutil verify "$out" >/dev/null
echo "Created $out ($(du -h "$out" | cut -f1))"
