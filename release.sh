#!/bin/bash
# Builds a release MacWine.app and packages it into a (non-notarized,
# ad-hoc-signed) DMG with a drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")"

APP="MacWine.app"
DMG="MacWine.dmg"

./bundle.sh release

# Ad-hoc sign so the bundle is internally consistent (still NOT notarized).
codesign --force --deep --sign - "$APP" 2>/dev/null || true

STAGE="$(mktemp -d)/MacWine"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "MacWine" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
