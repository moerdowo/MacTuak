#!/bin/bash
# Builds MacTuak and wraps the binary in a double-clickable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacTuak"

APP="MacTuak.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacTuak"
[ -f icon/AppIcon.icns ] && cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -d licenses ] && cp -R licenses "$APP/Contents/Resources/licenses"

# Bundled CLI helpers winetricks needs (cabextract, 7-Zip) — no Homebrew required.
if [ -d vendor ]; then
  mkdir -p "$APP/Contents/Resources/tools"
  cp vendor/cabextract "$APP/Contents/Resources/tools/cabextract"
  cp vendor/7za        "$APP/Contents/Resources/tools/7za"
  ln -sf 7za           "$APP/Contents/Resources/tools/7z"
  # 0755 (owner-writable) so `xattr -dr` and runtime de-quarantine can modify them.
  chmod 755 "$APP/Contents/Resources/tools/cabextract" "$APP/Contents/Resources/tools/7za"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacTuak</string>
  <key>CFBundleDisplayName</key><string>MacTuak</string>
  <key>CFBundleIdentifier</key><string>com.mactuak.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>MacTuak</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built $APP"
