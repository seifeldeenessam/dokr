#!/usr/bin/env bash
# Builds Dokr with SwiftPM and wraps it into build/Dokr.app.
#   CONFIG=release|debug   UNIVERSAL=1   VERSION=0.1.0   BUNDLE_ID=...   SIGN_IDENTITY="Developer ID Application: ..."
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Dokr
CONFIG=${CONFIG:-release}
VERSION=${VERSION:-0.1.0}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
BUNDLE_ID=${BUNDLE_ID:-com.seifeldeenessam.dokr}
SIGN_IDENTITY=${SIGN_IDENTITY:--}

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# Helper binary that Dokr copies into every generated folder .app.
cp "$BIN_DIR/DokrFolder" "$APP/Contents/MacOS/DokrFolder"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/DokrFolder"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP"
