#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
STATE_DIR="/tmp/fission-verification-${UID}"
RESULT_BUNDLE="$STATE_DIR/FissionDesktopUITests.xcresult"
mkdir -p "$STATE_DIR"
rm -rf "$RESULT_BUNDLE"

selection=()
for test_identifier in "$@"; do
  selection+=("-only-testing:$test_identifier")
done
if [[ ${#selection[@]} -eq 0 ]]; then
  selection+=("-only-testing:FissionDesktopUITests")
fi

status=0
xcodebuild \
  -project "$ROOT/Apps/Desktop/FissionDesktop.xcodeproj" \
  -scheme FissionDesktop \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/Apps/Desktop/.derivedData" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -parallel-testing-enabled NO \
  "${selection[@]}" \
  test || status=$?

printf 'Result bundle: %s\n' "$RESULT_BUNDLE"
exit "$status"
