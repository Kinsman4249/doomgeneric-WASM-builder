# DOOM in the browser (doomgeneric + Emscripten, no server required)

This repo builds [doomgeneric](https://github.com/ozkl/doomgeneric), a portable
fork of id Software's original 1997 linuxdoom source release, into a single
WebAssembly file that runs entirely inside your browser.

What you get:

1. No web server needed. Open `index.html` directly using a `file://` URL.
2. Load any WAD at runtime through a file picker in the page, plus optional
   PWADs (mods and maps) and DeHackEd patches (.deh) on top. HACX 1.2 works
   as a standalone IWAD. Nothing is baked into the build and nothing is
   uploaded anywhere.
3. Optional one-click free games. If you let the installer download the
   freeware pack, the setup screen offers Doom shareware, Freedoom Phase 1
   and 2, HACX, the Chex Quest Trilogy, Harmony, WolfenDoom: First
   Encounter, and STRAIN as buttons, no files to find. They live next to
   the build, never in any repository.
4. In-browser key remapping, in addition to Doom's own in-game
   Options, Customize Controls menu.
5. Window scaling with pixel filters. The game fills the browser window, and
   you choose between "Crisp" (the classic chunky pixels), "Smooth"
   (softened), and three GPU upscalers in 2x, 4x, and 8x variants: hq2x,
   xBR, and DCCI. Switch live while playing.
6. Full mouse look, GZDoom style. Click the game to capture the mouse: moving
   it turns AND looks up and down, and both mouse buttons shoot. Horizontal
   and vertical sensitivity are separate (seven steps each), and raw input
   (no mouse acceleration) is on by default. This goes beyond what the stock
   engine can do; the build script patches the engine source to add it (see
   "What is patched in the engine source").
7. An optional packaging step that turns the build into a ready-to-upload
   website folder (all paths relative, works on any domain or subfolder).
8. An FPS counter, read from a frame counter inside the engine itself and
   toggleable from the in-game bar.
9. Doom-plus style limit removal: vanilla's 1994-sized static arrays are
   enlarged 8x-32x so slaughter-grade maps (huge monster counts, complex
   geometry) stop crashing, without changing gameplay behavior.
10. DeHackEd and WAD merging support, so classic total conversions load with
    their graphics intact.

## How the build is organized

`install.sh` is a thin orchestrator: it sources `scripts/lib/common.sh` for
shared config and logging, then runs the numbered step scripts in
`scripts/steps/` in order (packages, emsdk, source, engine patch, DeHackEd,
Makefile, index.html, freeware pack, build, web deploy, packaging, cleanup).
The files it writes each run (`index.html`, `Makefile.emscripten`, the
engine patch, the freeware downloader) are real, editable files under
`assets/`, not generated inline, so if you want to change them, edit the
file under `assets/` directly and rebuild. That keeps a single source of
truth without needing one enormous script.

## Prerequisites

Supported systems: Fedora/RHEL family (dnf) and Debian/Ubuntu family
(apt-get). The script reads `/etc/os-release`, picks the right package
manager and package names automatically, and refuses clearly on anything
else rather than guessing.

On an immutable or atomic Linux host (for example Bazzite or Silverblue)
where you cannot install packages directly, build inside a Distrobox
container:

```bash
distrobox create --name doombuild --image fedora:latest
distrobox enter doombuild
```

A Debian or Ubuntu container (or plain machine) works the same way. On a
regular mutable system you can skip Distrobox and run `install.sh`
directly.

## Usage

```bash
git clone https://github.com/Kinsman4249/doomgeneric-WASM-builder.git
cd doomgeneric-WASM-builder
chmod +x install.sh
./install.sh
```

The script is idempotent, which means it is safe to re-run. Each step checks
whether its work is already done before doing it again. In order, it will:

1. Detect your distro family and install any missing required packages
   (Fedora: `git make cmake python3 gcc gcc-c++ patch` via dnf; Debian:
   `git make cmake python3 build-essential patch` via apt-get).
2. Clone the Emscripten SDK into `~/emsdk` if not already present, then
   install and activate a pinned, known-good release of it (see "Why the
   toolchain is pinned" below).
3. Add the emsdk environment to `~/.bashrc` and `~/.bash_profile` so that
   `emcc` is available in future shells without any manual step.
4. Clone `doomgeneric` into `~/doomgeneric` if not already present, reset it
   to a pinned commit, and apply the mouse-look engine patches (see "What is
   patched in the engine source" below).
5. Write a patched `Makefile.emscripten` (see "What is patched" below).
6. Write `index.html` (the WAD picker, controls UI, and display controls).
7. Build and verify. The output is `~/doomgeneric/doomgeneric/doomgeneric.js`
   and `index.html`. The paths to everything, including the downloaded
   freeware games, are printed at the end.
8. Optionally deploy into an existing Apache or Nginx site on this
   machine (see "Deploying into an existing web server" below). Control
   with `WEBEXPORT=1` or `WEBEXPORT=0`, or answer the prompt.
9. Optionally package everything (page, engine, freeware pack) into a
   ready-to-upload `site/` folder plus a `doom-site.tar.gz`. All paths in
   the page are relative, so the folder works on any domain, any
   subdirectory, any static host, with zero configuration. Control with
   `SITE=1` or `SITE=0`, or answer the prompt.
10. If a web deploy happened, optionally clean up the local copies (see
    "Cleanup after deploying" below). Control with `CLEANUP=1` or
    `CLEANUP=0`, or answer the prompt.

When it finishes, open `~/doomgeneric/doomgeneric/index.html` directly in a
browser. If the container shares your home directory with the host (the
Distrobox default), that same path exists on your host too, so you can open it
from your host file manager or browser.

## Prebuilt installers (no build required)

Every tagged release publishes three ready-to-run installers, built by CI
from the exact same `install.sh`/engine patch/index.html this repo ships,
so you do not need Fedora, Debian, Distrobox, or the Emscripten toolchain
just to play. Grab one from the
[Releases page](https://github.com/Kinsman4249/doomgeneric-WASM-builder/releases):

- **Linux**: a self-extracting `.run` file (built with makeself). Run it
  (`bash doomgeneric-WASM-*-linux.run`); it installs to
  `~/.local/share/doomgeneric-WASM` and adds a "DOOM (WASM)" entry to your
  application menu and Desktop, and prompts you (one yes/no per title) to
  download any of the free games below straight into the install.
  **To uninstall**: use the "Uninstall DOOM (WASM)" entry in your
  application menu, or run
  `~/.local/share/doomgeneric-WASM/uninstall.sh`.
- **Windows**: a `.exe` installer (built with NSIS). It installs to
  `%LOCALAPPDATA%\doomgeneric-WASM`, adds Desktop and Start Menu
  shortcuts, and its Components page lets you check off any of the free
  games below to download during install. It is unsigned, so Windows
  SmartScreen may warn on first run ("More info" > "Run anyway").
  **To uninstall**: Settings > Apps > "DOOM (WASM)" > Uninstall (or
  Control Panel > Programs and Features), or the Start Menu's
  "Uninstall" shortcut.
- **macOS**: a `.dmg` disk image containing a "DOOM (WASM)" app and a
  "Download Extra WADs.command" script. Drag the app to Applications as
  usual, then (optionally) double-click "Download Extra WADs.command" and
  answer yes/no per title to fetch any of the free games below into the
  installed app. It is unsigned and not notarized (no Apple Developer
  account behind this project), so the first launch needs right-click >
  Open, or a pass through System Settings > Privacy & Security >
  "Open Anyway". **To uninstall**: drag the app to the Trash - the
  downloaded WADs live inside it, so nothing is left behind.

None of the three bundle freeware games by default (keeps the installers
small); the prompts above download exactly the same titles `install.sh`'s
own freeware pack step offers - Doom shareware, Freedoom Phase 1 and 2,
HACX, the Chex Quest Trilogy, Harmony, WolfenDoom: First Encounter, and
STRAIN - fetched from their original sources at install time. Skip them all
and use the in-browser WAD picker instead if you'd rather supply your own
WAD.

### About resolution

There is nothing to configure. The vanilla renderer always draws the game
at the original 320x200, and the build runs the engine at exactly that
size: earlier versions offered a bigger frame buffer option, but it only
produced an enlarged copy of the same image while costing memory and a
multi-megabyte copy every frame, so it was removed. All upscaling happens
in the page: the display scaling fills your window (see "Display" below)
and the GPU filters work from the true 320x200 picture.

## Playing

1. Click "Load a WAD" and pick a `.wad` file. Use one you legally own, or the
   freely redistributable shareware `doom1.wad`. Optionally add PWADs (see
   "Loading PWADs and DeHackEd patches" below).
2. Optionally edit the key bindings (see "Default controls" below) and the
   mouse sensitivity or invert setting.
3. Optionally pick a pixel filter and aspect ratio. You can also change these
   while playing.
4. Click "Start DOOM".
5. Click the game once to capture the mouse. From then on the mouse looks
   around and both mouse buttons shoot. Esc releases the mouse (and opens
   Doom's menu).
6. Quitting from Doom's own menu (Options, Quit Game) returns to this setup
   screen. Your WAD selections and settings stay as they were, and Start
   boots a fresh game. The short pause with a sound right after confirming
   the quit is Doom's classic quit jingle, not a hang.

### Default controls

Mouse (after clicking the game once to capture it):

1. Move mouse: turn, and look up and down
2. Left or right mouse button: shoot
3. Esc: release the mouse (also opens Doom's menu)

Keyboard defaults are WASD with strafing on A and D, since the mouse covers
turning:

1. Move Forward: `KeyW`
2. Move Backward: `KeyS`
3. Strafe Left: `KeyA`
4. Strafe Right: `KeyD`
5. Turn Left: `ArrowLeft`
6. Turn Right: `ArrowRight`
7. Fire: `KeyF`
8. Use or Open (doors and switches): `KeyE`

The key binding fields use JavaScript `KeyboardEvent.code` names, for example
`KeyW`, `ArrowUp`, `Space`, or `ControlLeft`. Internally the page remaps each
physical key onto a key the engine understands: `F` onto Left Ctrl (Doom's
Fire), `E` onto Space (Doom's Use), and `A`/`D` onto Comma/Period (Doom's
classic strafe keys, which the engine patch wires up for the browser). So `E`
really does trigger Use, not Fire, and `A`/`D` really do strafe.

Doom's own Options, Customize Controls menu also works in game and persists to
the in-memory config file for the session. The page level remap decides which
physical key is reported to the engine. The in-game menu decides what a (real
or remapped) key does. Combine both if you need finer control than the page UI
offers.

### Mouse look

Clicking the game captures the mouse with the browser's pointer lock, the
same mechanism every browser shooter uses. While captured, horizontal motion
turns and vertical motion looks up and down, GZDoom style. Esc always
releases the mouse; that is a browser rule no page can override, and it
conveniently doubles as opening Doom's own menu. Click the game again to
recapture.

Horizontal (turning) and vertical (looking) sensitivity are separate
settings, each with seven steps (Extra low, Low, Normal, High, Higher, Very
high, Extra high). The defaults are Sens X High and Sens Y Low, which suits
mouse-look play: quick turning with restrained vertical aim. Both can be set
on the setup screen or changed live from the bar at the top of the screen.
"Invert mouse look" on the setup screen flips the vertical axis.

"Raw input (disable mouse acceleration)" is on by default: it asks the
browser for unaccelerated mouse motion (the pointer lock unadjustedMovement
option), so a flick of the wrist moves the view the same amount no matter
how fast the flick was. Most desktop browsers support it; if yours refuses,
the game quietly falls back to normal accelerated motion and logs a note in
the console. The setting takes effect the next time you capture the mouse,
so if you toggle it mid-game, press Esc and click back in.

Two honest limitations of bolting vertical look onto the 1993 renderer with
y-shearing (the same technique Heretic and Hexen used): the view pitch is
clamped to a comfortable range rather than a full 90 degrees up and down, and
the sky texture can look stretched or tiled when looking far up. Both are
normal for this technique.

### Display: scaling and pixel filters

The game canvas is scaled to fill the browser window. A small control bar
sits at the top of the screen while you play. It is nearly invisible during
play so it never distracts; move the mouse over it and it comes back to full
strength. It offers:

1. Pixel filter:
   - "Crisp (original pixels)" uses nearest-neighbour scaling. This keeps the
     classic large, sharp Doom pixels. This is closest to the original look.
   - "Smooth" uses the browser's built-in bilinear smoothing, which blends the
     pixels for a softer image.
   - "hq2x", "xBR", and "DCCI" are GPU upscalers (WebGL shaders) with
     edge-aware interpolation, the same family of filters emulators use,
     each in 2x, 4x, and 8x variants (the filter applied one, two, or
     three times over). 8x pays off mainly on large or high-DPI displays,
     where it replaces the browser's final blur-up with filter-built
     detail; on a laptop screen 4x usually looks the same. The engine
     always renders the classic 320x200 picture internally, so the shaders
     recover that true image through the engine's integer enlargement and
     upscale it properly; earlier versions filtered the already-fattened
     pixels, which visibly did almost nothing. hq2x rounds pixel-art
     edges, xBR keeps sharper diagonals, DCCI is a smooth directional
     cubic look. If your browser has no usable WebGL, these fall back to
     Smooth automatically.
2. Aspect:
   - "4:3 (original look)" matches how Doom was shown on period monitors.
   - "Square pixels" displays the buffer without stretching.
3. Sens X and Sens Y: horizontal (turning) and vertical (looking) mouse
   sensitivity, seven steps each from Extra low to Extra high. Defaults are
   Sens X High and Sens Y Low (fast turning, gentle vertical aim).
4. FPS: shows or hides a performance readout in the top right corner, with
   two numbers sampled once a second from counters inside the engine:
   - "FPS" is how often the engine renders, which the browser drives.
   - "game: N/35" is game-logic speed in tics per second. 35 is full speed.
     Fewer means the map is too heavy to simulate in real time and the game
     is running in slow motion; the page itself stays responsive (see
     "Performance notes").
5. Fullscreen: a button that toggles true fullscreen.

You can also set all of these on the setup screen before you start. Changing
a control takes effect immediately, so you can compare presets live. While
the mouse is captured by the game, press Esc first to free it, adjust the
bar, then click the game to recapture.

### Loading PWADs and DeHackEd patches (mods)

Next to the main WAD picker there is an optional picker for PWADs, add-on
WAD files with extra maps or content. You can select several; they load on
top of the main WAD in selection order using the engine's `-file` option.
Two vanilla-engine caveats:

1. PWADs need a full IWAD (registered, retail, Freedoom, and so on). The
   shareware `doom1.wad` refuses add-on files by design; the setup screen
   catches that combination before starting.
2. Plain `-file` loading cannot fold a PWAD's replacement sprites and
   flats into the game; that is a vanilla WAD-loader fact. For total
   conversions that replace graphics, tick "total conversion (merge)"
   next to the PWAD picker: it uses the restored `-merge` loader instead,
   which handles them properly. Plain map and level PWADs are fine either
   way.

DeHackEd is fully supported. DeHackEd patches (.deh files) are how classic
mods change monster behavior, weapon stats, and game text. The build
restores the parser from Chocolate Doom (doomgeneric had deleted it while
keeping all the integration code), which enables all of the following:

1. A .deh file picker next to the PWAD picker. Patches apply in selection
   order via the engine's `-deh` option.
2. PWADs that carry a DEHACKED lump have it applied automatically.
3. The HACX 1.2 standalone IWAD works: the engine recognizes `hacx.wad`
   and loads its built-in DEHACKED lump by itself.
4. Freedoom's built-in DEHACKED lump now applies, so its texts are correct.
5. The ORIGINAL 1996 `chex.wad` IWAD, if you supply it yourself, works
   when you also add its required patch through the picker with the exact
   filename `chex.deh` (files keep their names for this reason). The Chex
   Quest Trilogy button needs none of this; it ships its own patch.
6. Load order matches classic behavior: the IWAD's own patch first, then
   your .deh files, then PWAD DEHACKED lumps.

A malformed patch stops the engine with a parse error, which the page shows
in its red error box including the offending line.

### One-click free games

If you answer yes to the freeware pack when running `install.sh`, the setup
screen shows a row of buttons that load a game in one click, with no files to
hunt down. The games are downloaded next to the build (never into any
repository) and packed as data the page loads locally, so this still works
over `file://` with no server. Each game only occupies memory while you are
actually playing it.

- Doom Shareware, Freedoom Phase 1, Freedoom Phase 2, and HACX 1.2 load
  directly as their own IWADs.
- The Chex Quest Trilogy button is Chex Quest 3: Vanilla Edition (Melodic
  Spaceship, 2024), a self-contained backport of all three Chex Quests to
  this exact engine class, loaded as its own IWAD with the plain-DeHackEd
  patch its readme prescribes for Chocolate-class engines. The title
  screen says Chex Quest 3 because that is the game it is built from; the
  EPISODES are the individual quests (Episode 1 is Chex Quest, Episode 2
  is Chex Quest 2, Episode 3 is Chex Quest 3's campaign), picked from the
  New Game menu. Chex Quest was
  a freeware cereal promotion, and Chex Quest 3 was made officially free by
  General Mills in 2019; the backport's readme is installed in the pack
  folder.
- Harmony loads as a total conversion over Freedoom Phase 2 the same way.
- WolfenDoom: First Encounter (Laz Rojas' faithful recreation of the
  Wolfenstein 3D demo episode) loads as a total conversion over Freedoom
  Phase 2. It is a fan work using id's own Wolfenstein designs, distributed
  with the author's stated permission; his readme is installed in the pack
  folder, as his distribution terms ask.
- STRAIN (1997, Alpha Dog Alliance) loads as a total conversion over
  Freedoom Phase 2, with its extensive DeHackEd patch applied. Its
  distribution terms permit free electronic distribution provided the text
  file and the entire package are included unmodified, so the pack stores
  the complete original archive untouched alongside the loader files.

Loading a free game replaces anything you picked by hand above. If a button
reports the game is missing, re-run `install.sh` and answer yes to the
freeware pack (it only downloads what is not already there).

(The ORIGINAL Chex Quest 3 release is a ZDoom-engine game, Hexen map
format and all, which a vanilla engine cannot run. That is exactly why the
pack ships the Vanilla Edition backport above instead of the original.)

Merging total conversions is possible because the build also restores the
engine's `-merge` support (see "What is patched in the engine source"),
which folds a PWAD's sprites and flats into the IWAD the way the classic
deutex tool did. This is what lets Harmony, WolfenDoom, and STRAIN look
right rather than showing Freedoom graphics. The same loader is available
for your own files: tick "total conversion (merge)" next to the PWAD
picker.

A few famous total conversions are linked from the setup screen as reading
material but deliberately NOT offered as downloads: Aliens TC (1994),
Batman Doom (1999, ACE Team), and Star Wars for Doom II (1998). All run on
this engine class, but all are based on film and comics properties, so
their licensing is murkier than the officially freeware pack above. The
page links where to read up (Doom Wiki articles, and the Doomworld archive
page for Star Wars) so players can research and decide for themselves; if
obtained, they load through the PWAD picker with the total-conversion box
ticked (Batman Doom also wants its .deh file).

One format caveat that neither limit removal nor DeHackEd changes: this
engine only understands VANILLA map behavior. Many modern community WADs
(including most slaughter megawads such as Cleanout) are built in the Boom
format and need a Boom-compatible port. On this engine, Boom-only switch
and walk triggers silently do nothing (breaking progression), and stepping
into a sector with a Boom-only sector type stops the game with
"P_PlayerInSpecialSector: unknown special". Pick WADs whose readme says
vanilla, limit-removing, or complevel 2/3; "Boom" or "complevel 9" WADs are
out of scope for this engine.

### Why the on-screen size scales at runtime but the rendering does not

The vanilla renderer always draws the game at 320x200, and that cannot
change while the game runs, so the page scales the finished frame to fill
the window using CSS, and the pixel filters decide how that scaling looks.
The GPU filters work from the same true 320x200 image.

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

## Why the toolchain is pinned

The script installs Emscripten SDK release 3.1.64, not "latest". A newer
release produced builds that crashed at startup in some browsers, with errors
like these in the console:

```text
TypeError: Failed to execute 'decode' on 'TextDecoder': The provided
ArrayBuffer value must not be resizable
```

```text
Unsafe attempt to load URL file:///.../index.html from frame with URL
file:///.../index.html. 'file:' URLs are treated as unique security origins.
```

The first happens when a newer runtime asks the browser's TextDecoder to read
strings out of memory that can grow, which some browsers refuse. The second
happens when a newer runtime attempts a network style load, which browsers
block on `file://` pages. Pinning the toolchain avoids both, and it also makes
builds reproducible: the same script always produces the same result instead
of whatever happened to be released last week. Both errors were hit in the
wild on this exact project, and rebuilding with the pinned toolchain resolved
them.

If you built with an older copy of this script (which used "latest"), pull the
latest version of this repo and re-run `./install.sh`. SDK releases install
side by side, the script activates the pinned one, and every build starts with
a clean step, so the fix applies automatically. Then reload `index.html` with a
hard refresh (Ctrl+Shift+R) so the browser does not reuse a cached copy of the
old `doomgeneric.js`.

Two extra safety nets ship with the page. The setup screen shows a "Build:"
line with the SDK version and build time, so you can confirm at a glance that
you are looking at a fresh page and not a cached one. And the page wraps the
browser's TextDecoder so that text read from growable memory is copied first,
which means even an engine build from an incompatible toolchain cannot crash
on the error above.

To experiment with a different SDK release anyway:

```bash
EMSDK_VERSION=4.0.10 ./install.sh
```

If a much newer SDK rejects the `TEXTDECODER` setting, remove that flag from
the Makefile section of `install.sh` and rebuild.

## Change history

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.

## Deploying into an existing web server

If this machine already runs Apache or Nginx, the installer can place the
build inside one of its existing sites. Answer yes to the deploy prompt
(or set `WEBEXPORT=1`) and it will:

1. Detect installed servers (Debian: `apache2`, Fedora: `httpd`, and
   `nginx` on both), then read their enabled site configs
   (`sites-enabled` on Debian, `conf.d` on Fedora) for document roots and
   server names.
2. Show a numbered menu of discovered sites, plus "enter a path manually"
   and "skip".
3. Copy `index.html`, `doomgeneric.js`, and the freeware pack (if
   downloaded) into a `doomgeneric-WASM/` subfolder of the chosen site
   root. Nothing else in the site root is touched, and re-running
   replaces that subfolder cleanly.
4. Set least-privilege static-site permissions (directories 755, files
   644) owned by the account the server runs as (`www-data` on Debian,
   `apache` or `nginx` on Fedora), and on Fedora restore the SELinux
   context so the server may read the files.

The server's own configuration is never modified and nothing is
reloaded: whatever address already serves that site root simply gains a
`/doomgeneric-WASM/` path. DNS and vhosts remain your business.

## Deploying to Cloudflare Pages

Every tagged release (`git tag vX.Y.Z && git push --tags`) can also deploy
the playable site straight to Cloudflare Pages. The `deploy-cloudflare-pages`
job in `.github/workflows/release.yml` downloads the freeware pack fresh on
the GitHub Actions runner and uploads it straight to Cloudflare's API - the
WAD files are never committed to this repo, never a release asset, and never
stored in git history anywhere. If the secrets below are not set, the job
prints a warning and skips itself; it does not fail the release.

This is a one-time setup. Cloudflare's dashboard reorganizes itself
periodically, so if a menu below has moved, search the dashboard for the
same words (e.g. "API Tokens", "Pages").

### 1. Create the Pages project

1. Go to <https://dash.cloudflare.com>, log in, and pick your account if
   asked.
2. Left sidebar: **Workers & Pages**.
3. Click **Create** (top right), then the **Pages** tab.
4. Click **Upload assets** (NOT "Connect to Git" - the GitHub Actions job
   uploads directly, so Cloudflare does not need its own copy of this repo
   or a build step on Cloudflare's side).
5. Give it a project name, e.g. `doomgeneric-wasm`. Write this down; it is
   the `CLOUDFLARE_PAGES_PROJECT` secret in step 4.
6. On the upload screen, drag in any single file (e.g. this README) just to
   get past the wizard and create the project - the real deploy comes from
   GitHub Actions afterward and will replace it.
7. Click **Deploy site**.

Pitfall: the **Create** button's default tab is often **Workers**, not
**Pages** - if you land on a project whose URL is
`<random-words>.<subdomain>.workers.dev` instead of
`<project-name>.pages.dev`, you made a Worker by mistake (it also has a
lower free-tier request cap: 100,000/day account-wide, versus Pages'
unmetered requests). Delete it and redo step 3-4, making sure the **Pages**
tab is selected before clicking **Upload assets**. A project at
`<name>.pages.dev` (e.g. `doom-8j2.pages.dev`) is a correctly-created Pages
project - use that `.pages.dev` prefix (`doom-8j2` in that example) as the
`CLOUDFLARE_PAGES_PROJECT` secret value.

### 2. Create an API token

1. Click your profile icon (top right) > **My Profile**.
2. Left sidebar: **API Tokens**.
3. Click **Create Token**.
4. Find the **"Edit Cloudflare Workers"** template and click **Use
   template**. (Despite the name, this template's permissions also cover
   Pages. If you would rather scope it tighter: use **Custom token** and
   add the permission **Account > Cloudflare Pages > Edit**.)
5. Under **Account Resources**, restrict it to your specific account rather
   than "All accounts" if given the choice.
6. Click **Continue to summary**, then **Create Token**.
7. Copy the token now - Cloudflare shows it exactly once. If you lose it,
   delete the token and make a new one.

### 3. Find your Account ID

1. Still in the Cloudflare dashboard, go to **Workers & Pages** (left
   sidebar).
2. The **Account ID** is shown in the right-hand sidebar of that page (also
   visible on most other dashboard pages in the same spot). Copy it.

### 4. Add the three GitHub secrets

1. Open this repo on GitHub.
2. **Settings** (top tab) > **Secrets and variables** (left sidebar) >
   **Actions**.
3. Click **New repository secret** three times, once per row:

   | Secret name                | Value                                   |
   |-----------------------------|------------------------------------------|
   | `CLOUDFLARE_API_TOKEN`      | the token from step 2                    |
   | `CLOUDFLARE_ACCOUNT_ID`     | the account ID from step 3               |
   | `CLOUDFLARE_PAGES_PROJECT`  | the project name from step 1 (e.g. `doomgeneric-wasm`) |

4. Push a version tag (or re-run the `Release` workflow from the Actions
   tab against an existing tag). The `Deploy (Cloudflare Pages)` job runs
   alongside the installer builds, and the site goes live at
   `https://<project-name>.pages.dev` (a custom domain can be attached
   under the Pages project's **Custom domains** tab afterward).

## Cleanup after deploying

Offered only when a web deploy actually completed. After verifying the
deployed copy really exists and is non-empty, it deletes the local build
artifacts (`doomgeneric.js`, `index.html`, the object directory, and the
downloaded freeware pack) and prints the exact list of what was removed.
Two things are never deleted without their own separate confirmation: the
packaged `site/` folder and tarball from the packaging step, and the
cloned source repo (removing the source means re-cloning before you can
rebuild). Declining cleanup leaves everything in place.

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

## Legal note

The doomgeneric engine source, and the underlying Doom engine, is GPL licensed
code. Game data (WAD files) is separate copyrighted content. Only load a WAD you
legally own, or the freely distributable shareware `doom1.wad`.

## Troubleshooting

1. `emcc: command not found` right after `./emsdk activate`. The activate
   step only prints instructions, it does not change your current shell. Run
   `source ~/emsdk/emsdk_env.sh` in the current shell, or open a new shell if
   you already added the sourcing line to `.bashrc`.

2. `git`, `make`, or similar "command not found" in a fresh Distrobox
   container. The container was created without those packages. Run
   `sudo dnf install -y git make cmake python3 gcc gcc-c++ patch`. If `sudo` is
   not set up in the container, run `distrobox enter <name> --root` and install
   as root.

3. `emcc: error: customizing EXPORT_NAME requires that the HTML be customized to
   use that name`. This happens if Emscripten emits its own default HTML shell
   while a custom `EXPORT_NAME` is set. This repo avoids it by outputting `.js`
   only and shipping a hand-written `index.html`.

4. Arrow keys, Space, or F keys scroll the page or trigger browser shortcuts
   instead of controlling the game. The page cancels the browser's default
   action for every key Doom reacts to (see `BASE_MANAGED_CODES` in the
   generated `index.html`), and this interception is active whenever the game is
   running (tracked by the `gameStarted` flag). If you still see this, make sure
   the game actually started (the setup screen should be gone).

5. The whole browser tab closes while playing. This is not a bug in the page. If
   your physical key choices happen to form a browser reserved shortcut when
   held together (most notably Ctrl+W, Ctrl+T, Ctrl+N, or Ctrl+Q in Chrome),
   the browser acts on it before page JavaScript runs, and `preventDefault`
   cannot override it. This is intentional browser behavior. The default Fire
   binding is `KeyF` on purpose, to avoid pairing a real Left Ctrl with `KeyW`
   (Move Forward), which would physically be Ctrl+W. If you remap Fire to a
   modifier key such as Left Ctrl while another binding uses a letter that forms
   a reserved combo, expect this to happen again. Pick a plain letter or Space
   for any binding that might be held at the same time as another.

6. The game looks blurry and you wanted sharp pixels, or looks harsh and you
   wanted it softer. Use the "Filter" control at the top of the screen. "Crisp"
   is the sharp original look, "Smooth" is the blended look.

7. Moving the mouse does nothing. The mouse only reaches the game while it is
   captured: click the game once (the hint at the bottom of the screen shows
   whenever capture is off). If clicking does not capture, make sure the tab
   is focused; some browsers also briefly refuse recapture right after Esc,
   so wait a moment and click again.

8. The mouse turns but E opens the menu, or keys act strangely right after
   capturing. Click squarely on the game canvas, not the control bar, and
   check the bindings on the setup screen before starting.

9. Looking up shows a stretched or repeating sky. Normal for y-sheared
   vertical look on the 1993 software renderer (Heretic had the same). The
   view pitch is deliberately clamped to keep the effect reasonable.

10. Fire keeps going after Esc. The page releases all mouse buttons when
    capture ends, so this should not happen; if it does, click the game,
    press and release both mouse buttons once, and please open an issue
    with your browser name and version.

11. "You cannot -file with the shareware version" when starting with PWADs
    selected. That is the engine refusing by design: add-on files require a
    full IWAD (registered, retail, or Freedoom), not the shareware
    `doom1.wad`. The setup screen now detects this combination up front
    (it reads the WAD's lump directory the same way the engine does) and
    shows a warning instead of starting, so you should normally never see
    the engine version of this error anymore.

12. A PWAD loads but replaced sprites or floor textures look unchanged.
    Plain `-file` loading cannot fold those in; tick "total conversion
    (merge)" next to the PWAD picker and start again.

13. Crashes that the limit removal fixed, for reference when testing. If a
    build BEFORE the limit patch died on a big map, the red error box or
    console showed one of these: "R_FindPlane: no more visplanes" (the
    classic one), "P_AddActivePlat: no more plats!", "P_StartButton: no
    button slots left!", or "Savegame buffer overrun" when saving. Spechit
    and intercepts overflows had no message at all, just corruption or a
    random crash during heavy movement or BFG shots. If you see any of
    these on a current build, rebuild and check the build stamp date; if it
    persists on a fresh build, open an issue with the map name.

14. A big map dies with "P_PlayerInSpecialSector: unknown special" or its
    switches and doors simply do nothing. That is a Boom-format map, which
    this vanilla engine does not support; no limit setting fixes that. See
    the format caveat under "Loading PWADs (mods)".

15. `RuntimeError: function signature mismatch` in an older build whenever
    the engine hit any error. Fixed by an engine patch: vanilla registered
    a boolean-returning function as an exit handler through a cast, which
    x86 tolerates but WebAssembly traps on, so every engine error crashed
    opaquely instead of exiting with its message. Engine errors now exit
    cleanly, and the page shows the engine's own output in the red error
    box (plus a watchdog catches the case where the engine stops before
    rendering its first frame).

16. A warning about `emscripten_set_main_loop_timing` and "a main loop does
    not exist" appears in the console at boot. Harmless: SDL tries to set
    its frame timing before the engine's main loop is registered a moment
    later. It has always been there and affects nothing.

17. "You cannot -file with the shareware version" even though the main WAD
    is a full doom.wad or doom2.wad. Old builds of this page presented
    every chosen WAD to the engine under the name doom1.wad, and the
    engine identifies WADs by filename, so everything ran as shareware
    Doom 1. Fixed: the page now presents the WAD under its correct name
    (check the console line "IWAD will be presented to the engine as").
    If you still see this on a current build, your WAD really is the
    shareware one; the setup screen warning will say so.

18. The game froze the whole tab on a heavy map (huge monster counts).
    Old builds compiled without optimization AND let the engine try to
    catch up on missed game tics without limit, so an overloaded frame
    grew more overloaded forever. Fixed twice over: builds now use -O2,
    and catch-up is capped so overload plays as slow motion instead
    (watch "game: N/35" in the FPS readout drop below 35 while the page
    stays responsive). If the readout sits at 35/35 and it still feels
    wrong, that is something else; open an issue with the map name.

19. The build fails compiling `deh_io.c` with "member reference type
    'lumpinfo_t' ... is not a pointer". A cached Chocolate Doom clone from
    an older build is the wrong release. Pull the latest version of this
    repo and re-run `./install.sh`: the cache now checks its own release
    tag and refreshes itself. (Manual fix, equivalent: delete the
    `chocolate-deh-src` folder inside your doomgeneric checkout and
    re-run.)

20. `TypeError: Failed to execute 'decode' on 'TextDecoder': The provided
    ArrayBuffer value must not be resizable` in the console, and the game
    never starts. The build was made with a too-new Emscripten toolchain
    whose runtime some browsers reject. Pull the latest version of this repo,
    re-run `./install.sh` (it pins a known-good toolchain and always rebuilds
    from a clean step), then hard refresh the page (Ctrl+Shift+R). See "Why
    the toolchain is pinned".

    If you rebuilt and the error is still there, you are almost certainly
    running the old files. Check three things:

    - The setup screen should show a "Build:" line at the bottom with the
      pinned SDK version and a fresh build time. No line at all means the
      page is the old version. An old time means a stale cached page.
    - Run `grep -c UTF8Decoder ~/doomgeneric/doomgeneric/doomgeneric.js`
      in the container. A fresh pinned build prints `0`. (Do not grep for
      plain "TextDecoder": the word also appears in harmless comments.)
    - Close the game's browser tab completely and open `index.html` again. A
      plain reload can serve a cached copy on `file://` pages.

21. `Unsafe attempt to load URL file:///... 'file:' URLs are treated as
    unique security origins` in the console. Same cause and same fix as the
    previous entry: a too-new runtime attempted a network style load, which
    browsers do not allow on `file://` pages. The pinned toolchain embeds
    everything inside `doomgeneric.js` and never needs to load anything at
    runtime, which is what makes the no-server design work.
