[Back to README](../README.md)

# Engine and build patches

## What is patched in `Makefile.emscripten`

The upstream `Makefile.emscripten` is written for a native Linux build. It asks
the host's `sdl2-config` for flags (wrong for a WebAssembly target) and it
produces a default `.html`, `.wasm`, and `.data` set that needs a real web
server. The generated version in this repo changes the following:

1. Uses Emscripten's own SDL2 and SDL2_mixer ports (`-s USE_SDL=2 -s
   USE_SDL_MIXER=2`) instead of the host `sdl2-config`.
2. Embeds the `.wasm` inside the `.js` (`-s SINGLE_FILE=1`) so there is no
   separate binary to fetch, which is what makes it work over `file://`.
3. Keeps the virtual filesystem API linked in (`-s FORCE_FILESYSTEM=1`) so the
   page can write a WAD into memory at runtime.
4. Allows WebAssembly memory to grow (`-s ALLOW_MEMORY_GROWTH=1`) so loading a
   large PWAD at runtime does not run out of heap.
5. Exposes the module as `DoomModule(...)` (`-s MODULARIZE=1 -s
   EXPORT_NAME="DoomModule"`) instead of using global scope.
6. Stops `main()` from auto-running on load (`-s INVOKE_RUN=0`) so the page can
   write the WAD in first and then start the engine.
7. Outputs `.js` instead of `.html`, because once `EXPORT_NAME` is customized
   Emscripten's default HTML shell no longer works. This repo ships its own
   `index.html` instead.
8. Puts linker settings such as `SDL2_MIXER_FORMATS` in the link flags rather
   than the compile flags, so MIDI music support is actually wired in and the
   compiler does not warn on every file.
9. Targets browsers only (`-s ENVIRONMENT=web`), which strips runtime code
   paths meant for Node.js and workers. Those paths have a history of
   attempting loads that browsers block on `file://` pages.
10. Uses Emscripten's plain JavaScript string decoder (`-s TEXTDECODER=0`)
    instead of the browser's TextDecoder, because some browsers refuse
    TextDecoder on memory that can grow, which crashes the game at startup.
11. Exports the page-facing engine functions alongside `main`: the two
    mouse-bridge calls (`DG_EM_MouseMove`, `DG_EM_MouseButtons`) and the
    frame-counter getter (`DG_EM_GetFrameCount`) behind the FPS display.

No backup file is needed anymore: the script resets the source to the pinned
upstream commit with git before writing this file, every run.

## What is patched in the engine source

The stock engine has no mouse support in its browser port, and the 1993
renderer cannot look up and down at all. `install.sh` fixes both by applying
a source patch (embedded in the script, applied with `patch -p1`) right after
resetting the clone to the pinned commit. Because the source is reset first,
the patch always applies to pristine files no matter how many times the
script runs. What the patch does, file by file:

1. `doomgeneric_emscripten.c` (the browser platform layer): adds the mouse
   bridge. The page calls two exported functions with captured mouse motion
   and button state; the bridge accumulates them and posts one standard Doom
   mouse event per rendered frame. Also maps the Comma and Period keys to
   Doom's dedicated strafe key codes (the classic keyboard layout strafed on
   `,` and `.`), which is what the page's A and D bindings ride on. Also
   counts rendered frames and exports a getter, which is what the page's
   FPS display reads.
2. `g_game.c`: vertical mouse motion now drives a new pitch variable
   (`lookdir`) instead of walking the player forward and back, which is what
   original Doom did with it. Mouse motion between game tics is accumulated
   instead of overwritten, so fast flicks are not partially lost (the game
   logic runs at 35 Hz while frames render faster). The pitch resets when a
   level starts.
3. `r_main.c`: applies the pitch with y-shearing, the same software-renderer
   technique Heretic and Hexen used: the projection horizon (`centery`)
   slides up or down the screen, and the `yslope` table that floor and
   ceiling rendering depends on is recomputed when the pitch or view size
   changes.
4. `r_things.c`: the weapon sprite would ride up and down with the sheared
   view; a compensation term holds it steady on screen (weapon bob still
   works).
5. DeHackEd and WAD-merge support restored. doomgeneric kept every line of
   Chocolate Doom's integration for both (the DeHackEd IWAD patch loader
   with its HACX, Freedoom, and Chex Quest handling, the `-deh` parser, the
   PWAD DEHACKED lump loader, and the `-merge` total-conversion loader) but
   fenced them off and deleted the implementation files. The patch re-opens
   the fences in `d_main.c` and flips `FEATURE_DEHACKED` and
   `FEATURE_WAD_MERGE` in `doomfeatures.h`; the implementation sources
   (`deh_*.c` and `w_merge.c`) are restored by `install.sh` from Chocolate
   Doom 2.2.1, the exact release this fork descends from. The vintage is
   confirmed byte-for-byte: the deh and merge headers still present in
   doomgeneric are identical to that release's, and the restored sources
   compile against this tree with no adaptation. WAD merging is what lets
   total conversions (Chex Quest, Harmony) display their own graphics
   instead of the base IWAD's.
6. Static limit removal, Doom-plus style, across several files. Vanilla
   Doom sized its arrays for 1994 maps; slaughter-grade community maps
   overflow them, which either crashes with an engine error or silently
   corrupts memory. Every change is a pure `#define` size bump (no code
   path changes, so gameplay and demo behavior stay identical), and
   Chocolate Doom's vanilla-overrun emulations (SpechitOverrun,
   InterceptsOverrun) are deliberately left untouched. The values:

   - `MAXVISPLANES` 128 to 4096 (`r_plane.c`): the classic slaughter crash,
     "R_FindPlane: no more visplanes".
   - `MAXOPENINGS` x8 (`r_plane.c`): clip-window buffer, unchecked write,
     overflow corrupts memory.
   - `MAXDRAWSEGS` 256 to 4096 (`r_defs.h`): overflow silently drops
     distant walls rather than crashing.
   - `MAXVISSPRITES` 128 to 2048 (`r_things.h`): overflow silently stops
     drawing monsters, which defeats slaughter testing.
   - `MAXSPECIALCROSS` 20 to 512 (`p_local.h`): the famous spechit
     overflow; the write has no bounds check, so exceeding it corrupts
     memory.
   - `MAXINTERCEPTS` plus 2048 slots (`p_local.h`): same class, triggered
     by BFG and hitscan traces through dense hordes.
   - `MAXPLATS` and `MAXCEILINGS` 30 to 512 (`p_spec.h`): overflow is a
     "no more plats!" crash and silently stuck ceilings respectively.
   - `MAXBUTTONS` 16 to 256 (`p_spec.h`): overflow is a "no button slots
     left!" crash.
   - `MAXLINEANIMS` 64 to 1024 (`p_spec.c`): lets big maps animate all
     their scrolling walls (this tree caps gracefully rather than
     crashing).
   - `SAVEGAMESIZE` x16 (`g_game.c`): saves are stream based here, but the
     vanilla size cap is still emulated with a "Savegame buffer overrun"
     error; the cap is raised 16x, Doom-plus style.

The engine source is pinned to a specific upstream commit (see
`DOOMGENERIC_COMMIT` in `install.sh`) so the patch always has the exact
context it was written against. After every build, the script verifies that
the page-facing engine functions actually got exported and stops with a
clear error if not.

## Performance notes

What the build does for speed, and what to expect on heavy maps:

1. The engine is compiled and linked with `-O2`. Earlier versions of this
   script set no optimization level at all, which means emcc's default of
   `-O0`, easily 5 to 20 times slower at runtime. This matters more than
   everything else combined.
2. The tic catch-up loop is capped (engine patch). Vanilla tries to run as
   many game tics per frame as real time says it owes; when one tic takes
   longer than a tic's worth of real time, the debt grows every frame and
   a browser tab freezes outright. Capped, the game runs in slow motion
   under overload, exactly like DOS Doom on a slow machine, and the page
   stays responsive. Single player only; netgame sync logic is untouched.
3. The zone allocator default grows from 6 MiB (a 1993 number) to 64 MiB,
   the C stack is 1 MiB, and the WebAssembly memory starts at 128 MiB so
   memory growth does not pause the game mid fight.
4. The FPS readout shows game speed beside render speed ("game: N/35").
   On something like NUTS.wad, expect full speed while monsters are asleep
   and a slow-motion dip when thousands wake at once; that is the 1993
   simulation loop meeting 10000 monsters, not a bug in the build. There
   is no further honest speedup available without changing how the game
   itself simulates and renders, which this project deliberately does not
   do: the point is the original engine, running anywhere.
