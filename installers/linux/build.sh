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

# Bundled so the end user's machine can fetch optional WADs at install time
# without needing network access to this repo. Same script install.sh
# (the dev build) uses, just invoked with a subset of keys - see its own
# header comment for the download plan.
cp "assets/freeware_pack.py" "$STAGE_DIR/freeware_pack.py"

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

# ---------------------------------------------------------------------------
# Optional freeware WADs, picked per title. Each title maps to a group of
# freeware_pack.py keys (some titles are a base IWAD plus a merge/DeHackEd
# patch - see assets/freeware_pack.py's PLAN and assets/index.html's
# FREEWARE_TITLES, which this list matches).
#
# Non-interactive runs (no TTY, e.g. piped installs) skip all titles by
# default; set WAD_<KEY>=1 (e.g. WAD_DOOM1=1) beforehand to opt one in
# without a prompt, or WAD_<KEY>=0 to force-skip one during an interactive
# run.
# ---------------------------------------------------------------------------
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
  varname="WAD_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
  choice="${!varname:-}"
  if [ -z "$choice" ]; then
    if [ -t 0 ]; then
      read -r -p "Download $label? [y/N]: " ans
      case "$ans" in [Yy]*) choice=1 ;; *) choice=0 ;; esac
    else
      choice=0
    fi
  fi
  if [ "$choice" = "1" ]; then
    # shellcheck disable=SC2207
    SELECTED_KEYS+=($(expand_keys "$key"))
  fi
done

if [ "${#SELECTED_KEYS[@]}" -gt 0 ]; then
  if command -v python3 >/dev/null 2>&1; then
    echo "Downloading selected WADs..."
    mkdir -p "$INSTALL_DIR/freeware"
    python3 ./freeware_pack.py "$INSTALL_DIR/freeware" "${SELECTED_KEYS[@]}" || \
      echo "Some downloads failed; the page will say so per title. Re-run this .run file to retry."
  else
    echo "python3 not found: skipping WAD downloads. Install python3 and re-run this .run file to add them."
  fi
fi

# ---------------------------------------------------------------------------
# Uninstaller: removes the install dir, the app-menu entry, and the desktop
# shortcut. Also gets its own app-menu entry so it's reachable without a
# terminal, mirroring the Start Menu "Uninstall" shortcut on Windows.
# ---------------------------------------------------------------------------
cat > "$INSTALL_DIR/uninstall.sh" << UNINSTALL_EOF
#!/usr/bin/env bash
set -euo pipefail
rm -rf "$INSTALL_DIR"
rm -f "$APPS_DIR/doomgeneric-wasm.desktop"
rm -f "$APPS_DIR/doomgeneric-wasm-uninstall.desktop"
rm -f "$DESKTOP_TARGET/doomgeneric-wasm.desktop"
echo "DOOM (WASM) has been uninstalled."
UNINSTALL_EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# A separate launcher (rather than an inline "Exec=bash -c '...'") because
# the Desktop Entry spec's Exec quoting only understands double quotes, not
# single quotes - a plain script path avoids that trap entirely.
cat > "$INSTALL_DIR/uninstall-launcher.sh" << LAUNCHER_EOF
#!/usr/bin/env bash
"$INSTALL_DIR/uninstall.sh"
read -r -p "Press Enter to close..."
LAUNCHER_EOF
chmod +x "$INSTALL_DIR/uninstall-launcher.sh"

cat > "$APPS_DIR/doomgeneric-wasm-uninstall.desktop" << UNINSTALL_DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Uninstall DOOM (WASM)
Comment=Remove DOOM (WASM) and its game files
Exec="$INSTALL_DIR/uninstall-launcher.sh"
Terminal=true
Categories=Game;
UNINSTALL_DESKTOP_EOF
chmod +x "$APPS_DIR/doomgeneric-wasm-uninstall.desktop"

echo ""
echo "Installed to $INSTALL_DIR"
echo "Launch it from your application menu, the desktop icon, or by opening:"
echo "  $INSTALL_DIR/index.html"
echo ""
echo "To uninstall: use \"Uninstall DOOM (WASM)\" in your application menu,"
echo "or run: $INSTALL_DIR/uninstall.sh"
INSTALL_EOF
chmod +x "$STAGE_DIR/install.sh"

MAKESELF="$(command -v makeself.sh || command -v makeself)"
"$MAKESELF" --gzip "$STAGE_DIR" "$OUT_DIR/doomgeneric-WASM-${VERSION}-linux.run" \
  "DOOM (WASM) installer" ./install.sh

echo "Built $OUT_DIR/doomgeneric-WASM-${VERSION}-linux.run"
