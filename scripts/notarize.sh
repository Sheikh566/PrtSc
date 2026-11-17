#!/usr/bin/env bash
# Notarize a .app, .dmg, .zip or .pkg with `xcrun notarytool`, then staple the ticket.
#
# Usage: scripts/notarize.sh <path>
#   A .app is zipped with ditto for upload; the ticket is stapled to the .app itself.
#
# Credentials (environment), either:
#   APPLE_API_KEY_ID + APPLE_API_ISSUER_ID + APPLE_API_KEY_P8   (App Store Connect API key;
#                                                               APPLE_API_KEY_P8 is the key file
#                                                               contents, plain or base64)
# or:
#   APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID               (app-specific password)
#
# The thing being notarized must already be signed with a Developer ID identity,
# hardened runtime and a secure timestamp (scripts/sign-app.sh does that).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

target="$1"
[[ -e "$target" ]] || { echo "error: $target does not exist" >&2; exit 66; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

auth=()
if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" && -n "${APPLE_API_KEY_P8:-}" ]]; then
  if [[ "$APPLE_API_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
    printf '%s\n' "$APPLE_API_KEY_P8" > "$tmp/key.p8"
  else
    printf '%s' "$APPLE_API_KEY_P8" | base64 --decode > "$tmp/key.p8"
  fi
  auth=(--key "$tmp/key.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  auth=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
  echo "error: no notarization credentials in the environment (see header of $0)" >&2
  exit 78
fi

upload="$target"
if [[ -d "$target" && "$target" == *.app ]]; then
  upload="$tmp/$(basename "$target" .app).zip"
  ditto -c -k --keepParent "$target" "$upload"
fi

echo "Submitting $upload to the notary service (this can take a few minutes)..."
xcrun notarytool submit "$upload" "${auth[@]}" --wait --output-format json > "$tmp/result.json" || true
cat "$tmp/result.json"

status="$(sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p' "$tmp/result.json" | head -n 1)"
id="$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' "$tmp/result.json" | head -n 1)"
if [[ "$status" != "Accepted" ]]; then
  echo "error: notarization status is '${status:-unknown}'" >&2
  if [[ -n "$id" ]]; then
    xcrun notarytool log "$id" "${auth[@]}" >&2 || true
  fi
  exit 1
fi

xcrun stapler staple "$target"
xcrun stapler validate "$target"
echo "Notarized and stapled $target"
