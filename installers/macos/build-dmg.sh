#!/usr/bin/env bash
# build-dmg.sh - package the built web payload into a minimal macOS .app
# bundle (a launcher shell script plus the payload, no compiling) and wrap
# it in a drag-to-Applications .dmg.
#
# Run from the repo root on a macOS runner, with the payload already
# downloaded into payload/. Produces dist/doomgeneric-WASM-<version>-macos.dmg
set -euo pipefail

VERSION="${1:?usage: build-dmg.sh <version>}"
APP_NAME="DOOM (WASM)"
OUT_DIR="dist"
STAGE_DIR="$(mktemp -d)"
APP_DIR="$STAGE_DIR/${APP_NAME}.app"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p "$OUT_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp payload/index.html payload/doomgeneric.js "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/MacOS/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
open "$DIR/index.html"
LAUNCH_EOF
chmod +x "$APP_DIR/Contents/MacOS/launch.sh"

ICON_KEY=""
if [ -f "assets/icon.png" ]; then
  ICONSET="$STAGE_DIR/icon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "assets/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "assets/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/icon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>icon.icns</string>"
fi

cat > "$APP_DIR/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>launch.sh</string>
  <key>CFBundleIdentifier</key><string>com.kinsman4249.doomgeneric-wasm</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
  ${ICON_KEY}
</dict>
</plist>
PLIST_EOF

DMG_ROOT="$STAGE_DIR/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO \
  "$OUT_DIR/doomgeneric-WASM-${VERSION}-macos.dmg"

echo "Built $OUT_DIR/doomgeneric-WASM-${VERSION}-macos.dmg"
