#!/usr/bin/env bash
# Sign an update archive (the .dmg) with Sparkle's EdDSA key and print the values the
# appcast needs.
#
# Usage: scripts/sparkle-sign.sh <file.dmg>
#
# Environment:
#   SPARKLE_ED_PRIVATE_KEY  the private key string printed by `generate_keys -x` (CI secret).
#                           If unset, sign_update falls back to the key in your login keychain
#                           (where generate_keys put it), which is convenient locally.
# Output (stdout, two lines, eval-safe):
#   ED_SIGNATURE=<base64>
#   LENGTH=<bytes>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

file="$1"
[[ -f "$file" ]] || { echo "error: $file not found" >&2; exit 66; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sign_update="$("$here/sparkle-tool.sh" sign_update)"

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  out="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$file")"
else
  out="$("$sign_update" "$file")"
fi

# sign_update prints: sparkle:edSignature="..." length="..."
signature="$(printf '%s\n' "$out" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"
length="$(printf '%s\n' "$out" | sed -n 's/.*length="\([0-9]*\)".*/\1/p' | head -n 1)"

if [[ -z "$signature" || -z "$length" ]]; then
  echo "error: could not parse sign_update output: $out" >&2
  exit 1
fi

echo "ED_SIGNATURE=$signature"
echo "LENGTH=$length"
