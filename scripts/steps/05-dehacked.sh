# 05-dehacked.sh - restore the DeHackEd parser and WAD-merge sources from
# Chocolate Doom.
#
# doomgeneric descends from Chocolate Doom but deleted the DeHackEd parser
# implementation files (only the headers and the integration code remain).
# DeHackEd patches (.deh) are how classic mods change monster behavior,
# weapon stats, and text: HACX, Chex Quest, Freedoom, and countless mods
# rely on them. We restore the implementation from Chocolate Doom at the
# exact release this fork descends from (verified: the deh headers that
# remain in doomgeneric are byte-identical to that release), so the files
# drop straight in. Pinned to a tag for reproducibility, cached like the
# other clones, re-copied on every run so the result is always consistent.
CHOCO_TAG="chocolate-doom-2.2.1"
CHOCO_DIR="$DOOMGENERIC_DIR/chocolate-deh-src"

# The cache is keyed on the release tag through a marker file. This matters:
# the pinned tag changed once already (2.3.0 to 2.2.1, whose sources drop in
# with zero adaptations), and a cache from before the change shipped the
# wrong vintage and broke the build with a pointer-versus-struct error in
# deh_io.c. A wrong or missing marker refreshes the clone.
if [ ! -d "$CHOCO_DIR" ] \
   || [ "$(cat "$CHOCO_DIR/.wasm-builder-tag" 2>/dev/null)" != "$CHOCO_TAG" ]; then
  log "Fetching the DeHackEd implementation (Chocolate Doom $CHOCO_TAG)..."
  rm -rf "$CHOCO_DIR"
  git clone --quiet --depth 1 --branch "$CHOCO_TAG" \
    https://github.com/chocolate-doom/chocolate-doom.git "$CHOCO_DIR"
  echo "$CHOCO_TAG" > "$CHOCO_DIR/.wasm-builder-tag"
else
  log "Chocolate Doom sources already fetched at $CHOCO_DIR ($CHOCO_TAG)."
fi

log "Installing DeHackEd parser and WAD-merge sources into the engine..."
# Shared parser core (the three deh headers already in doomgeneric are kept;
# they match this release byte for byte, which is how the vintage was
# confirmed). w_merge.c provides the -merge option: it loads total
# conversion PWADs with their sprites and flats intact, something the plain
# vanilla loader cannot do.
cp "$CHOCO_DIR/src/deh_defs.h" "$CHOCO_DIR/src/deh_io.h" \
   "$CHOCO_DIR/src/deh_mapping.h" "$CHOCO_DIR/src/deh_io.c" \
   "$CHOCO_DIR/src/deh_main.c" "$CHOCO_DIR/src/deh_mapping.c" \
   "$CHOCO_DIR/src/deh_str.c" "$CHOCO_DIR/src/deh_text.c" \
   "$CHOCO_DIR/src/w_merge.c" doomgeneric/
# Doom-specific section parsers (things, frames, weapons, ammo, cheats...).
cp "$CHOCO_DIR"/src/doom/deh_*.c doomgeneric/

# All of the buildable C sources live in the inner "doomgeneric" folder.
BUILD_DIR="$DOOMGENERIC_DIR/doomgeneric"
cd "$BUILD_DIR"

# Sanity: the DeHackEd sources must be in place before the build.
if [ ! -f deh_main.c ] || [ ! -f deh_defs.h ] || [ ! -f w_merge.c ]; then
  die "DeHackEd or WAD-merge sources missing after the copy step. Check the Chocolate Doom clone at $CHOCO_DIR."
fi

# Vintage guard: newer Chocolate releases use a pointer-style WAD directory
# (lumpinfo[n]->name) that this engine's struct-style directory cannot
# compile. If this fires, the cached clone is the wrong release; the marker
# logic above should make that impossible, but a clear message beats a
# compiler error.
if grep -q 'lumpinfo\[lumpnum\]->name' deh_io.c; then
  die "The fetched deh_io.c is from the wrong Chocolate Doom release. Delete $CHOCO_DIR and re-run this script."
fi
