# 09-build.sh - build the engine and verify the output.
cd "$BUILD_DIR"
log "Building (emmake make -f Makefile.emscripten)..."
emmake make -f Makefile.emscripten clean
emmake make -f Makefile.emscripten

# Sanity check: the linker should have produced doomgeneric.js.
if [ ! -f "$BUILD_DIR/doomgeneric.js" ]; then
  die "Build finished but doomgeneric.js was not produced. Check the make output above."
fi

# Verify the TEXTDECODER=0 setting actually took effect. The marker to look
# for is "UTF8Decoder", the runtime's cached TextDecoder instance: it only
# exists when the string code path we opted out of was emitted. (Plain
# "TextDecoder" also appears in harmless comments, so do not grep for that.)
# The page's shim keeps even a bad build from crashing, but it is unexpected
# with the pinned toolchain, so say something.
if grep -q "UTF8Decoder" "$BUILD_DIR/doomgeneric.js"; then
  warn "doomgeneric.js still contains the TextDecoder string path. The page"
  warn "ships a shim that keeps this from crashing, but it is unexpected with"
  warn "the pinned toolchain. See docs/TROUBLESHOOTING.md."
else
  log "Verified: doomgeneric.js uses the plain JS string decoder (as intended)."
fi

# Verify the page-facing engine exports made it into the build: the page
# calls these from JavaScript, so mouse input and the FPS counter are broken
# if the linker dropped any of them.
if grep -q "_DG_EM_MouseMove" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_MouseButtons" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_GetFrameCount" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_GetGameTic" "$BUILD_DIR/doomgeneric.js"; then
  log "Verified: mouse bridge and performance counter functions are exported."
else
  die "Engine exports missing from doomgeneric.js. The engine patch or EXPORTED_FUNCTIONS list did not take effect."
fi

log "Build complete."
echo ""
echo "  $BUILD_DIR/doomgeneric.js   (engine, with the .wasm embedded inside)"
echo "  $BUILD_DIR/index.html       (the page you open to play)"
if [ -d "$BUILD_DIR/freeware" ]; then
  echo "  $BUILD_DIR/freeware/        (the downloaded free games)"
fi
echo ""
echo "Open index.html directly in a browser (double-click it, or drag it into a"
echo "tab). No web server required."
