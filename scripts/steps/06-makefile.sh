# 06-makefile.sh - install the patched Makefile.emscripten.
#
# The upstream Makefile.emscripten is written for a native Linux build: it asks
# the HOST's "sdl2-config" for compiler flags (wrong for a WASM target) and it
# emits a default .html/.wasm/.data trio that needs a real web server. We
# replace it with a version (assets/Makefile.emscripten.tmpl) that uses
# Emscripten's own bundled SDL2 ports and produces a single self-contained
# .js file that works straight from file://.
#
# (No backup file is needed: the git reset in 03-source.sh already restored
# the pristine upstream Makefile before this rewrite, every run.)
cd "$BUILD_DIR"
log "Writing patched Makefile.emscripten..."
cp "$SCRIPT_DIR/assets/Makefile.emscripten.tmpl" Makefile.emscripten
