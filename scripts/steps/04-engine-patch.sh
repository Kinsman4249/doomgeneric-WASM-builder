# 04-engine-patch.sh - apply the mouse look / frame counter / limit removal
# patch to the pristine doomgeneric source.
#
# The stock engine has no mouse support in its browser port, and vanilla Doom
# cannot look up and down at all. This patch (assets/engine.patch) adds:
#   - a mouse bridge in the platform layer: the web page calls two exported
#     functions (DG_EM_MouseMove / DG_EM_MouseButtons) and the bridge posts
#     standard Doom mouse events to the engine (horizontal motion turns,
#     button bit 0 fires, which the page maps to both mouse buttons),
#   - vertical look, GZDoom style: mouse Y pitches the view using y-shearing
#     (the same software-renderer trick Heretic and Hexen used), with the
#     weapon sprite held steady on screen while the view shears,
#   - strafe key codes for , and . so the page can put strafing on A and D,
#   - mouse motion accumulation between game tics, so fast mouse movement is
#     not dropped (frames run faster than Doom's 35 Hz game logic),
#   - a rendered-frame counter the page reads to display an FPS counter,
#   - Doom-plus style static limit removal: vanilla arrays sized for 1994
#     maps (visplanes, drawsegs, openings, vissprites, spechit, intercepts,
#     plats, ceilings, buttons, line animations, savegame size) are enlarged
#     8x-32x so slaughter-grade maps stop crashing or corrupting memory.
#     Pure size bumps: no code paths change, gameplay stays identical, and
#     Chocolate Doom overrun EMULATIONS stay untouched,
#   - performance under overload: the tic catch-up loop is capped (an
#     overloaded frame runs slow motion instead of freezing the tab)
#     and the zone allocator default grows from 6 to 64 MiB,
#   - DeHackEd and WAD-merge (-merge) support re-enabled: doomgeneric
#     kept the integration for both but fenced it off and deleted the
#     implementations. See also the dehacked step below.
#   - (DeHackEd detail) doomgeneric kept all of Chocolate
#     Doom's DeHackEd integration but fenced it off and deleted the
#     parser sources. The patch re-opens the integration points and
#     turns the feature back on; the parser sources themselves are
#     restored from Chocolate Doom in the next step,
#   - a quit notifier: quitting from Doom's own menu calls a hook the
#     page installs, so the page can return to its setup screen,
#   - a game-tic counter export beside the frame counter, so the page
#     can show game speed (tics per second) next to FPS,
#   - a WebAssembly fix for the engine error path: vanilla registered a
#     boolean-returning function as a void exit handler through a cast,
#     which x86 tolerates but WASM rejects with a "function signature
#     mismatch" trap, turning every engine error into an opaque crash
#     instead of a clean exit with its real message.
#
# assets/engine.patch is a plain unified diff generated against the pinned
# commit in scripts/lib/common.sh; it is one logical change (one engine
# patch), so it stays as one file rather than being split further.
cd "$DOOMGENERIC_DIR"
log "Applying engine patch (mouse look, frame counter, limit removal)..."
patch -p1 < "$SCRIPT_DIR/assets/engine.patch"
