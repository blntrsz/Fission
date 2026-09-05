#!/usr/bin/env bash
set -euo pipefail

DERIVED_DATA="Apps/Desktop/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/Fission.app"
DIST_DIR="dist"
DMG_ROOT="$DIST_DIR/.dmg-root"
DMG_PATH="$DIST_DIR/Fission.dmg"
NOTARIZATION_ZIP="$DIST_DIR/Fission.app.zip"

build_settings=()
if [[ -n "${FISSION_BUILD_NUMBER:-}" ]]; then
  build_settings+=("CURRENT_PROJECT_VERSION=$FISSION_BUILD_NUMBER")
fi
if [[ -n "${FISSION_MARKETING_VERSION:-}" ]]; then
  build_settings+=("MARKETING_VERSION=$FISSION_MARKETING_VERSION")
fi
if [[ -n "${FISSION_UPDATE_FEED_URL:-}" ]]; then
  build_settings+=("FISSION_UPDATE_FEED_URL=$FISSION_UPDATE_FEED_URL")
fi
if [[ -n "${FISSION_SPARKLE_PUBLIC_KEY:-}" ]]; then
  build_settings+=("FISSION_SPARKLE_PUBLIC_KEY=$FISSION_SPARKLE_PUBLIC_KEY")
fi
if [[ -n "${FISSION_CODE_SIGN_IDENTITY:-}" ]]; then
  : "${FISSION_DEVELOPMENT_TEAM:?FISSION_DEVELOPMENT_TEAM is required for signed builds}"
  build_settings+=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=$FISSION_CODE_SIGN_IDENTITY"
    "DEVELOPMENT_TEAM=$FISSION_DEVELOPMENT_TEAM"
  )
fi

xcodebuild \
  -project Apps/Desktop/FissionDesktop.xcodeproj \
  -scheme FissionDesktop \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "${build_settings[@]}" \
  build

if [[ -n "${FISSION_UPDATE_FEED_URL:-}" || -n "${FISSION_SPARKLE_PUBLIC_KEY:-}" ]]; then
  : "${FISSION_UPDATE_FEED_URL:?FISSION_UPDATE_FEED_URL is required for update-enabled builds}"
  : "${FISSION_SPARKLE_PUBLIC_KEY:?FISSION_SPARKLE_PUBLIC_KEY is required for update-enabled builds}"
  info_plist="$APP_PATH/Contents/Info.plist"
  test "$(plutil -extract SUFeedURL raw -o - "$info_plist")" = "$FISSION_UPDATE_FEED_URL"
  test "$(plutil -extract SUPublicEDKey raw -o - "$info_plist")" = "$FISSION_SPARKLE_PUBLIC_KEY"
  test "$(plutil -extract SUEnableAutomaticChecks raw -o - "$info_plist")" = true
fi

notary_args=()
if [[ -n "${FISSION_NOTARY_KEYCHAIN:-}" ]]; then
  notary_args+=(--keychain "$FISSION_NOTARY_KEYCHAIN")
fi

if [[ -n "${FISSION_NOTARY_PROFILE:-}" ]]; then
  rm -f "$NOTARIZATION_ZIP"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARIZATION_ZIP"
  xcrun notarytool submit "$NOTARIZATION_ZIP" \
    --keychain-profile "$FISSION_NOTARY_PROFILE" \
    "${notary_args[@]}" \
    --wait
  xcrun stapler staple "$APP_PATH"
  rm -f "$NOTARIZATION_ZIP"
fi

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
trap 'rm -rf "$DMG_ROOT" "$NOTARIZATION_ZIP"' EXIT

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

if [[ -n "${FISSION_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$FISSION_NOTARY_PROFILE" \
    "${notary_args[@]}" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
if [[ -n "${FISSION_CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

echo "Created $DMG_PATH"
