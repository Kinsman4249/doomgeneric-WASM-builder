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

# Bundled so "Download Extra WADs.command" (below) can fetch optional
# freeware WADs straight into this app's Resources folder after install,
# using the machine's own python3 (macOS ships one; no extra tooling).
cp assets/freeware_pack.py "$APP_DIR/Contents/Resources/freeware_pack.py"

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

# A separate double-clickable script (Finder runs .command files in
# Terminal), rather than baking this into launch.sh, so the normal
# double-click-to-play path stays a plain, silent browser launch. Storing
# downloads inside the .app's own Resources means dragging the app to the
# Trash removes them too - no separate uninstall step needed.
cat > "$DMG_ROOT/Download Extra WADs.command" << 'WADS_EOF'
#!/bin/bash
set -euo pipefail

APP="/Applications/DOOM (WASM).app"
if [ ! -d "$APP" ]; then
  echo "\"DOOM (WASM)\" isn't in /Applications yet."
  echo "Drag it there from this disk image first, then run this again."
  read -r -p "Press Enter to close..."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. Install it (e.g. via Xcode Command Line Tools:"
  echo "  xcode-select --install) and run this again."
  read -r -p "Press Enter to close..."
  exit 1
fi

RESOURCES="$APP/Contents/Resources"
OUTDIR="$RESOURCES/freeware"

# Each title maps to a group of freeware_pack.py keys (some are a base
# IWAD plus a merge/DeHackEd patch) - matches assets/index.html's
# FREEWARE_TITLES and assets/freeware_pack.py's PLAN; keep the three
# in sync.
TITLE_KEYS=(doom1 freedoom1 freedoom2 hacx chex3v harmony wolfen1 strain)
TITLE_LABELS=(
  "Doom Shareware"
  "Freedoom Phase 1"
  "Freedoom Phase 2"
  "HACX 1.2"
  "Chex Quest Trilogy"
  "Harmony"
  "WolfenDoom: First Encounter"
  "STRAIN"
)

expand_keys() {
  case "$1" in
    doom1)     echo doom1 ;;
    freedoom1) echo freedoom1 ;;
    freedoom2) echo freedoom2 ;;
    hacx)      echo hacx ;;
    chex3v)    echo chex3v chex3v_deh chex3v_readme ;;
    harmony)   echo freedoom2 harmonyc harmony_deh ;;
    wolfen1)   echo freedoom2 wolfen1 wolfen1_readme ;;
    strain)    echo freedoom2 strain strain_deh strain_readme strain_package ;;
  esac
}

SELECTED_KEYS=()
for i in "${!TITLE_KEYS[@]}"; do
  key="${TITLE_KEYS[$i]}"
  label="${TITLE_LABELS[$i]}"
  read -r -p "Download $label? [y/N]: " ans
  case "$ans" in
    [Yy]*) SELECTED_KEYS+=($(expand_keys "$key")) ;;
  esac
done

if [ "${#SELECTED_KEYS[@]}" -gt 0 ]; then
  mkdir -p "$OUTDIR"
  echo "Downloading selected WADs..."
  python3 "$RESOURCES/freeware_pack.py" "$OUTDIR" "${SELECTED_KEYS[@]}" || \
    echo "Some downloads failed; the page will say so per title. Run this again to retry."
  echo "Done. Launch DOOM (WASM) to see the new titles as buttons on the setup screen."
else
  echo "Nothing selected."
fi
read -r -p "Press Enter to close..." || true
WADS_EOF
chmod +x "$DMG_ROOT/Download Extra WADs.command"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO \
  "$OUT_DIR/doomgeneric-WASM-${VERSION}-macos.dmg"

echo "Built $OUT_DIR/doomgeneric-WASM-${VERSION}-macos.dmg"
