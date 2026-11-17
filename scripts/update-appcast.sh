#!/usr/bin/env bash
# Add (or replace) a release <item> in a Sparkle 2 appcast.xml.
#
# Usage: scripts/update-appcast.sh --appcast <file> --version <x.y.z> --build <n> \
#            --url <dmg-url> --signature <edSignature> --length <bytes> \
#            [--notes-url <url>] [--min-os 26.0] [--date "<RFC 822 date>"]
#
#   --appcast    appcast.xml to update; created from packaging/appcast-template.xml if missing
#   --version    marketing version (sparkle:shortVersionString), e.g. 1.2.3
#   --build      build number (sparkle:version = CFBundleVersion); Sparkle compares this
#   --url        public download URL of the .dmg
#   --signature  EdDSA signature from scripts/sparkle-sign.sh
#   --length     size of the .dmg in bytes
#   --notes-url  release notes page (default: the GitHub release for v<version>)
#   --min-os     sparkle:minimumSystemVersion (default 26.0)
#   --date       pubDate (default: now, UTC)
#
# Re-running with the same --version replaces that item instead of duplicating it.
set -euo pipefail

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

appcast="" version="" build="" url="" signature="" length="" notes_url="" min_os="26.0" date=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --appcast) appcast="$2" ;;
    --version) version="$2" ;;
    --build) build="$2" ;;
    --url) url="$2" ;;
    --signature) signature="$2" ;;
    --length) length="$2" ;;
    --notes-url) notes_url="$2" ;;
    --min-os) min_os="$2" ;;
    --date) date="$2" ;;
    *) usage ;;
  esac
  shift 2
done

[[ -n "$appcast" && -n "$version" && -n "$build" && -n "$url" && -n "$signature" && -n "$length" ]] || usage

[[ "$version" =~ ^[0-9]+(\.[0-9]+)*([-.][0-9A-Za-z.]+)?$ ]] || { echo "error: bad version '$version'" >&2; exit 64; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "error: bad build '$build'" >&2; exit 64; }
[[ "$length" =~ ^[0-9]+$ ]] || { echo "error: bad length '$length'" >&2; exit 64; }
[[ "$signature" =~ ^[A-Za-z0-9+/=]+$ ]] || { echo "error: bad signature" >&2; exit 64; }
[[ "$min_os" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "error: bad --min-os '$min_os'" >&2; exit 64; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/packaging/appcast-template.xml"

: "${notes_url:=https://github.com/Sheikh566/PrtSc/releases/tag/v$version}"
: "${date:=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"

# Minimal XML escaping for the attribute/text values built from URLs.
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/item.xml" <<ITEM
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$(xml_escape "$notes_url")</sparkle:releaseNotesLink>
      <enclosure url="$(xml_escape "$url")"
                 length="$length"
                 type="application/octet-stream"
                 sparkle:edSignature="$signature"/>
    </item>
ITEM

if [[ ! -f "$appcast" ]]; then
  mkdir -p "$(dirname "$appcast")"
  cp "$template" "$appcast"
fi

grep -q '<!-- PRTSC-ITEMS -->' "$appcast" || {
  echo "error: $appcast has no '<!-- PRTSC-ITEMS -->' marker" >&2
  exit 1
}

awk -v ver="$version" -v itemfile="$tmp/item.xml" '
  /<item>/ { in_item = 1; buf = "" }
  in_item {
    buf = buf $0 "\n"
    if ($0 ~ /<\/item>/) {
      in_item = 0
      if (index(buf, "<sparkle:shortVersionString>" ver "</sparkle:shortVersionString>") == 0) printf "%s", buf
    }
    next
  }
  { print }
  /<!-- PRTSC-ITEMS -->/ {
    while ((getline line < itemfile) > 0) print line
    close(itemfile)
  }
' "$appcast" > "$tmp/new.xml"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$tmp/new.xml"
fi

cp "$tmp/new.xml" "$appcast"
echo "Updated $appcast with version $version (build $build)"
