#!/usr/bin/env bash
# Import a Developer ID certificate (.p12) into a temporary keychain and print the identity.
# Meant for CI; also works locally if you want an isolated keychain.
#
# Usage: scripts/import-cert.sh <keychain-path>
#
# Environment (required):
#   DEVELOPER_ID_CERT_P12       base64 of the .p12 file
#   DEVELOPER_ID_CERT_PASSWORD  password of the .p12
# Output: writes `identity=<Developer ID Application: ...>` and `keychain=<path>` to
#         $GITHUB_OUTPUT when set, otherwise prints the identity on stdout.
# Remove the keychain afterwards with: security delete-keychain <keychain-path>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

keychain="$1"
: "${DEVELOPER_ID_CERT_P12:?DEVELOPER_ID_CERT_P12 is not set}"
: "${DEVELOPER_ID_CERT_PASSWORD:?DEVELOPER_ID_CERT_PASSWORD is not set}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
password="$(uuidgen)"

printf '%s' "$DEVELOPER_ID_CERT_P12" | base64 --decode > "$tmp/cert.p12"

security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$tmp/cert.p12" -k "$keychain" -P "$DEVELOPER_ID_CERT_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null

# Put it on the search list so codesign finds it, keeping the existing keychains.
existing="$(security list-keychains -d user | tr -d '"' | xargs)"
# shellcheck disable=SC2086
security list-keychains -d user -s "$keychain" $existing

identity="$(security find-identity -v -p codesigning "$keychain" \
  | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -n 1)"
if [[ -z "$identity" ]]; then
  echo "error: no 'Developer ID Application' identity found in the .p12" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "identity=$identity"
    echo "keychain=$keychain"
  } >> "$GITHUB_OUTPUT"
else
  echo "$identity"
fi
