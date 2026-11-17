#!/usr/bin/env bash
# Code-sign PrtSc.app inside-out (Sparkle's helpers and framework first, the app last)
# with the hardened runtime.
#
# Usage: scripts/sign-app.sh <path/to/PrtSc.app> [identity]
#   identity  a codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#             Default "-" = ad-hoc signing (no certificate, no timestamp).
#
# With a real identity this also adds a secure timestamp, which notarization requires.
# Entitlements come from PrtSc/Resources/PrtSc.entitlements.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

app="$1"
identity="${2:--}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
entitlements="$repo_root/PrtSc/Resources/PrtSc.entitlements"

[[ -d "$app" ]] || { echo "error: $app is not a directory" >&2; exit 66; }

flags=(--force --options runtime --sign "$identity")
if [[ "$identity" != "-" ]]; then
  flags+=(--timestamp)
else
  flags+=(--timestamp=none)
fi

# Nested code, deepest path first. Only real directories/files are matched (-type), so the
# symlinks inside Sparkle.framework (Updater.app, Versions/Current, ...) are skipped and
# each piece of code is signed once. Sparkle's Autoupdate is a bare executable.
nested=()
while IFS= read -r path; do
  nested+=("$path")
done < <(
  find "$app/Contents" \
    \( \( -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) \) \
       -o \( -type f \( -name 'Autoupdate' -o -name '*.dylib' \) \) \) \
    -not -path "$app/Contents/MacOS/*" -print 2>/dev/null \
  | awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-
)

for path in ${nested[@]+"${nested[@]}"}; do
  echo "signing $path"
  # Keep the entitlements Sparkle ships on its XPC services (Downloader needs network access).
  codesign "${flags[@]}" --preserve-metadata=entitlements "$path"
done

echo "signing $app"
codesign "${flags[@]}" --entitlements "$entitlements" "$app"

codesign --verify --deep --strict --verbose=2 "$app"
echo "Signed $app with identity '$identity'"
