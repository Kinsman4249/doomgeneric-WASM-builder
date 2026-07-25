#!/usr/bin/env bash
# build.sh - package the built web payload (index.html, doomgeneric.js) into
# a self-extracting Linux installer using makeself.
#
# Run from the repo root, with the payload already downloaded into payload/
# (payload/index.html, payload/doomgeneric.js). Produces
# dist/doomgeneric-WASM-<version>-linux.run
set -euo pipefail

VERSION="${1:?usage: build.sh <version>}"
PAYLOAD_DIR="payload"
OUT_DIR="dist"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p "$OUT_DIR"
cp "$PAYLOAD_DIR/index.html" "$PAYLOAD_DIR/doomgeneric.js" "$STAGE_DIR/"

if [ -f "assets/icon.png" ]; then
  cp "assets/icon.png" "$STAGE_DIR/icon.png"
fi

# This script runs on the END USER's machine after makeself extracts the
# payload into a temp dir, not now. It is written as a literal (quoted
# heredoc), so nothing here is expanded at build time.
cat > "$STAGE_DIR/install.sh" << 'INSTALL_EOF'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/share/doomgeneric-WASM"
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$INSTALL_DIR" "$APPS_DIR"

cp index.html doomgeneric.js "$INSTALL_DIR/"

ICON_LINE=""
if [ -f icon.png ]; then
  cp icon.png "$INSTALL_DIR/icon.png"
  ICON_LINE="Icon=$INSTALL_DIR/icon.png"
fi

cat > "$APPS_DIR/doomgeneric-wasm.desktop" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=DOOM (WASM)
Comment=Browser-based WebAssembly build of doomgeneric
Exec=xdg-open "$INSTALL_DIR/index.html"
Terminal=false
Categories=Game;
$ICON_LINE
DESKTOP_EOF
chmod +x "$APPS_DIR/doomgeneric-wasm.desktop"

DESKTOP_TARGET="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [ -d "$DESKTOP_TARGET" ]; then
  cp "$APPS_DIR/doomgeneric-wasm.desktop" "$DESKTOP_TARGET/"
  chmod +x "$DESKTOP_TARGET/doomgeneric-wasm.desktop"
fi

echo ""
echo "Installed to $INSTALL_DIR"
echo "Launch it from your application menu, the desktop icon, or by opening:"
echo "  $INSTALL_DIR/index.html"
INSTALL_EOF
chmod +x "$STAGE_DIR/install.sh"

MAKESELF="$(command -v makeself.sh || command -v makeself)"
"$MAKESELF" --gzip "$STAGE_DIR" "$OUT_DIR/doomgeneric-WASM-${VERSION}-linux.run" \
  "DOOM (WASM) installer" ./install.sh

echo "Built $OUT_DIR/doomgeneric-WASM-${VERSION}-linux.run"
