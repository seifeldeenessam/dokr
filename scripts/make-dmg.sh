#!/usr/bin/env bash
# Packs build/Dokr.app into build/Dokr.dmg (drag-to-Applications layout).
#   SIGN_IDENTITY="Developer ID Application: ..."   signs the .dmg too (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Dokr.app
DMG=build/Dokr.dmg
[[ -d "$APP" ]] || { echo "Missing $APP — run ./scripts/bundle.sh first" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Dokr.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname Dokr -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "Built $DMG"
