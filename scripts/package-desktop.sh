#!/usr/bin/env bash
set -euo pipefail

DERIVED_DATA="Apps/Desktop/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/Fission.app"
DIST_DIR="dist"
DMG_ROOT="$DIST_DIR/.dmg-root"
DMG_PATH="$DIST_DIR/Fission.dmg"

build_settings=()
if [[ -n "${FISSION_BUILD_NUMBER:-}" ]]; then
  build_settings+=("CURRENT_PROJECT_VERSION=$FISSION_BUILD_NUMBER")
fi

xcodebuild \
  -project Apps/Desktop/FissionDesktop.xcodeproj \
  -scheme FissionDesktop \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "${build_settings[@]}" \
  build

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
trap 'rm -rf "$DMG_ROOT"' EXIT

ditto "$APP_PATH" "$DMG_ROOT/Fission.app"
ln -s /Applications "$DMG_ROOT/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
  -volname Fission \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo "Created $DMG_PATH"
