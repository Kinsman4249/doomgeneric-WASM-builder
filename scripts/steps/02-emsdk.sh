# 02-emsdk.sh - install and activate the Emscripten SDK (the C-to-WASM
# compiler), then make sure future shells get 'emcc' on PATH automatically.
if [ ! -d "$WASM_BUILDER_EMSDK_DIR" ]; then
  log "Cloning emsdk into $WASM_BUILDER_EMSDK_DIR..."
  git clone https://github.com/emscripten-core/emsdk.git "$WASM_BUILDER_EMSDK_DIR"
else
  log "emsdk already cloned at $WASM_BUILDER_EMSDK_DIR."
fi

cd "$WASM_BUILDER_EMSDK_DIR"
log "Installing/activating emsdk $EMSDK_VERSION (skips cleanly if already done)..."
# 'install' downloads that exact compiler release (a no-op if already there).
# 'activate' makes it the version that emsdk_env.sh puts on PATH.
# Releases install side by side, so switching between versions is cheap and
# does not remove anything you already have.
./emsdk install "$EMSDK_VERSION"
./emsdk activate "$EMSDK_VERSION"

# 'source' runs the given script in the CURRENT shell so that the emcc compiler
# is added to this shell's PATH. The 'shellcheck disable' comment silences a
# warning about not being able to follow the sourced file (it does not exist
# until emsdk is installed).
# shellcheck disable=SC1091
source "$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh"

# Confirm the compiler is really on PATH now; if not, stop with a clear error.
if ! command -v emcc >/dev/null 2>&1; then
  die "emcc still not on PATH after sourcing emsdk_env.sh. Something is wrong with the emsdk install."
fi
log "emcc available: $(emcc --version | head -n1)"

# Persist the emsdk environment so future shells get 'emcc' automatically.
# We append a small sourcing block to the user's shell startup files, but only
# once (the grep check makes this idempotent).
for RC in "$HOME/.bashrc" "$HOME/.bash_profile"; do
  LINE="source \"$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh\" > /dev/null 2>&1"
  if ! grep -qF "emsdk_env.sh" "$RC" 2>/dev/null; then
    log "Adding emsdk sourcing to $RC"
    {
      echo ""
      echo "# Emscripten SDK"
      echo "if [ -f \"$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh\" ]; then"
      echo "    $LINE"
      echo "fi"
    } >> "$RC"
  else
    log "$RC already sources emsdk_env.sh, skipping."
  fi
done
