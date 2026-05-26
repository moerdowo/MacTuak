#!/bin/bash
# Builds MacWine and wraps the binary in a double-clickable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacWine"

APP="MacWine.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacWine"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacWine</string>
  <key>CFBundleDisplayName</key><string>MacWine</string>
  <key>CFBundleIdentifier</key><string>com.macwine.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>MacWine</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built $APP"
