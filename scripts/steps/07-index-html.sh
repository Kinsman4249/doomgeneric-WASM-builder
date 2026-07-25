# 07-index-html.sh - install index.html (WAD picker + key remap UI + window
# scaling / filter presets) and stamp it with build info.
cd "$BUILD_DIR"
log "Writing index.html..."
cp "$SCRIPT_DIR/assets/index.html" index.html

# Stamp the page with build info. assets/index.html ships a literal
# __BUILD_INFO__ placeholder (no shell expansion happens while copying it),
# so we substitute it here instead. The stamp shows on the setup screen and
# in the browser console, which makes stale-cache and forgot-to-rebuild
# problems obvious at a glance.
BUILD_STAMP="emsdk ${EMSDK_VERSION}, doomgeneric ${DOOMGENERIC_COMMIT:0:7} patched, built $(date -u '+%Y-%m-%d %H:%M UTC')"
sed -i "s|__BUILD_INFO__|${BUILD_STAMP}|" index.html
log "Stamped index.html: ${BUILD_STAMP}"
