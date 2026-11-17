#!/usr/bin/env bash
# Archive the Release configuration of PrtSc and copy PrtSc.app to an output directory.
#
# Usage: scripts/build-app.sh <marketing-version> <build-number> <output-dir>
#   marketing-version  e.g. 1.2.3 (becomes MARKETING_VERSION / CFBundleShortVersionString)
#   build-number       integer, must increase every release (CURRENT_PROJECT_VERSION / CFBundleVersion,
#                      which is what Sparkle compares)
#   output-dir         PrtSc.app is copied here
#
# Environment:
#   BUILD_DIR  scratch directory for DerivedData and the .xcarchive (default: <repo>/build)
#
# The archive is built with code signing disabled; run scripts/sign-app.sh afterwards. That
# way ad-hoc and Developer ID builds go through exactly the same code path.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

version="$1"
build="$2"
out_dir="$3"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$repo_root/build}"
archive="$build_dir/PrtSc.xcarchive"

if [[ ! "$build" =~ ^[0-9]+$ ]]; then
  echo "error: build number must be an integer, got '$build'" >&2
  exit 64
fi

rm -rf "$archive"
mkdir -p "$out_dir"

# Pretty-print xcodebuild output when xcpretty is installed; xcodebuild's own exit status
# is preserved by pipefail either way.
formatter=cat
if command -v xcpretty >/dev/null 2>&1; then
  formatter=xcpretty
fi

xcodebuild archive \
  -project "$repo_root/PrtSc.xcodeproj" \
  -scheme PrtSc \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir/DerivedData" \
  -archivePath "$archive" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  | "$formatter"

app="$archive/Products/Applications/PrtSc.app"
if [[ ! -d "$app" ]]; then
  echo "error: archive did not produce $app" >&2
  exit 1
fi

rm -rf "$out_dir/PrtSc.app"
ditto "$app" "$out_dir/PrtSc.app"
echo "Built $out_dir/PrtSc.app ($version, build $build)"
