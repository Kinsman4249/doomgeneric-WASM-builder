[Back to README](../README.md)

# Troubleshooting

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
    the format caveat at the end of
    [Loading PWADs and DeHackEd patches](PLAYING.md#loading-pwads-and-dehacked-patches-mods).

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
    from a clean step), then hard refresh the page (Ctrl+Shift+R). See
    [Why the toolchain is pinned](BUILDING.md#why-the-toolchain-is-pinned).

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
