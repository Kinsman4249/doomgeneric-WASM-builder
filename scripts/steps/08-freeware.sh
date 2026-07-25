# 08-freeware.sh - optional freeware game pack.
#
# Downloads freely redistributable games next to the build output (NOT into
# any repository) and packs each file as base64 inside a small .js file.
# The page loads these with plain script tags, which work over file:// with
# no server and no network, so the setup screen gets one-click buttons for:
# Doom shareware, Freedoom Phase 1 and 2, HACX 1.2, the Chex Quest Trilogy
# (Chex Quest 3: Vanilla Edition, a self-contained IWAD), Harmony, STRAIN,
# and WolfenDoom: First Encounter (the latter three over Freedoom Phase 2,
# with authors' readmes installed alongside where their terms ask).
# Roughly 125 MB on disk; each game only costs RAM when actually clicked.
# Control with FREEWARE=1 (download) or FREEWARE=0 (skip); unset asks.
# The download/pack logic itself lives in assets/freeware_pack.py.
if [ -z "${FREEWARE:-}" ]; then
  if [ -t 0 ]; then
    read -r -p "Download the freeware game pack (~125 MB: Freedoom, shareware Doom, HACX, Chex Quest Trilogy, Harmony, WolfenDoom, STRAIN)? [Y/n]: " FW_ANS
    case "${FW_ANS:-Y}" in
      [Yy]*|"") FREEWARE=1 ;;
      *)        FREEWARE=0 ;;
    esac
  else
    FREEWARE=0
    log "Non-interactive run: skipping the freeware game pack (set FREEWARE=1 to include it)."
  fi
fi

if [ "$FREEWARE" = "1" ]; then
  log "Preparing the freeware game pack (skips files already packed)..."
  mkdir -p "$BUILD_DIR/freeware"
  python3 "$SCRIPT_DIR/assets/freeware_pack.py" "$BUILD_DIR/freeware"
  log "Freeware pack step finished."
  echo ""
  echo "  Downloaded game files are in:  $BUILD_DIR/freeware/"
  echo ""
else
  log "Freeware game pack skipped."
fi
