# 03-source.sh - clone (or reuse) the doomgeneric source and pin it to the
# exact commit the engine patch in assets/engine.patch is written against.
if [ ! -d "$DOOMGENERIC_DIR" ]; then
  log "Cloning doomgeneric into $DOOMGENERIC_DIR..."
  git clone https://github.com/ozkl/doomgeneric.git "$DOOMGENERIC_DIR"
else
  log "doomgeneric already cloned at $DOOMGENERIC_DIR."
fi

cd "$DOOMGENERIC_DIR"

# Make sure the pinned commit is available locally (a fetch is only needed if
# the clone predates the commit or was made from a different point in time).
if ! git cat-file -e "$DOOMGENERIC_COMMIT" 2>/dev/null; then
  log "Fetching doomgeneric history for pinned commit..."
  git fetch --quiet origin
fi

# Reset the source to the exact pinned commit. This throws away any tracked
# changes from previous runs of this script, which is what makes the patch
# step below safe to re-run: patches always apply to pristine source. Files
# git does not track (like the build output and our index.html) are kept.
log "Resetting doomgeneric source to pinned commit ${DOOMGENERIC_COMMIT:0:7}..."
git reset --hard --quiet "$DOOMGENERIC_COMMIT"
