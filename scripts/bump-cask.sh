#!/usr/bin/env bash
# Render packaging/Casks/prtsc.rb into a Homebrew cask file.
#
# Usage: scripts/bump-cask.sh --version <x.y.z> (--dmg <file> | --sha256 <hex>) --out <Casks/prtsc.rb> [--unsigned]
#
#   --version   release version without the leading "v"
#   --dmg       compute sha256 from this file (or pass --sha256 directly)
#   --out       destination, normally Casks/prtsc.rb in a checkout of Sheikh566/homebrew-tap
#   --unsigned  keep the postflight block that strips the quarantine flag (builds that are
#               not notarized); without it that block is removed
set -euo pipefail

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

version="" dmg="" sha="" out="" unsigned=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) unsigned=1; shift ;;
    --version|--dmg|--sha256|--out)
      [[ $# -ge 2 ]] || usage
      case "$1" in
        --version) version="$2" ;;
        --dmg) dmg="$2" ;;
        --sha256) sha="$2" ;;
        --out) out="$2" ;;
      esac
      shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$version" && -n "$out" && ( -n "$dmg" || -n "$sha" ) ]] || usage
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*([-.][0-9A-Za-z.]+)?$ ]] || { echo "error: bad version '$version'" >&2; exit 64; }

if [[ -z "$sha" ]]; then
  [[ -f "$dmg" ]] || { echo "error: $dmg not found" >&2; exit 66; }
  sha="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
fi
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "error: bad sha256 '$sha'" >&2; exit 64; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/packaging/Casks/prtsc.rb"

mkdir -p "$(dirname "$out")"
awk -v unsigned="$unsigned" '
  /# BEGIN UNSIGNED/ { skip = !unsigned; next }
  /# END UNSIGNED/   { skip = 0; next }
  !skip { print }
' "$template" \
  | sed -e "s/__VERSION__/$version/" -e "s/__SHA256__/$sha/" > "$out"

# Collapse the blank line left behind when the block is removed.
cat -s "$out" > "$out.tmp" && mv "$out.tmp" "$out"

if command -v ruby >/dev/null 2>&1; then
  ruby -c "$out" >/dev/null
fi
echo "Wrote $out (version $version, sha256 $sha)"
