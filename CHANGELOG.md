# Changelog

## Unreleased

Update WASM compilation and packaging step to work with CloudFlare Static Pages

## v2.3.0 (2026-07-29)

All three prebuilt installers (Linux, Windows, macOS) can now download and install optional freeware WADs at setup time. The Linux and macOS installers prompt the user yes/no per title; the Windows installer has a Components page with checkboxes. Titles available are Doom Shareware, Freedoom Phase 1 and 2, HACX, Chex Quest Trilogy, Harmony, WolfenDoom: First Encounter, and STRAIN, all fetched from their original sources (no bundled WAD files). Users can skip all downloads and use the in-browser picker instead to supply their own WAD.

The freeware download mechanism is shared across all three installers: assets/freeware_pack.py (Python) handles Linux and macOS downloads, and a new installers/windows/freeware-pack.ps1 (PowerShell) port handles Windows, both using the same PLAN of sources and filtering by title group as requested by the installer. The download happens at install time after the core is installed, so network failures during WAD fetches do not block the game itself.

The Windows installer workflow now uses NSIS 3's MUI2 wizard UI with a Components page instead of silent installation, and the NSIS script receives the version number from the CI job via the /DVERSION flag. The Windows installer also registers itself in Control Panel > Programs and Features with an uninstall entry. macOS gains a "Download Extra WADs.command" shell script in the .dmg alongside the app for optional post-install WAD downloads. Linux's uninstall.sh script now removes downloaded WAD files as part of cleanup.

## v2.2.1 (2026-07-25)

Fixed Windows installer build path: the NSIS installer script now correctly references the payload directory using backslash paths and runs from the proper working directory to resolve relative paths.

## v2.2.0 (2026-07-24)

The release workflow now builds and publishes three platform-specific installers alongside the source archive. Each tagged release now includes a self-extracting Linux installer (built with makeself), a Windows GUI installer (built with NSIS), and a macOS disk image containing an app bundle (built with hdiutil), all three built from the exact same engine and index.html. Users no longer need to install the Emscripten toolchain, Fedora, Debian, or Distrobox—they can download a ready-to-run installer for their platform from the Releases page.

The README now documents these prebuilt installers, including installation instructions and behavior notes (Linux adds a .desktop entry and app-menu shortcut, Windows adds Start Menu and Desktop shortcuts, macOS uses a standard drag-to-Applications .dmg). The build process includes optional icon support (assets/icon.png is automatically converted to .ico for Windows and .icns for macOS, with graceful fallback if the icon is missing).

The CI workflow was restructured into five jobs: a single upstream build-payload job that produces the web artifacts, three independent packaging jobs that download the payload and wrap it for their respective platforms, and a final release job that collects all three installers plus source archives and publishes one GitHub Release.

## Pre-2.2.0 history


Everything below landed on 2026-07-08. The startup crash fixes are confirmed
working: rebuilding with the pinned toolchain on an affected machine resolved
the crash and the game now runs.

### Input and build correctness (versus the original build)

1. Key interception activates based on whether the game has started, using a
   simple `gameStarted` flag, instead of checking which element has focus.
   The focus check was unreliable right after clicking Start, which let the
   browser eat arrow keys and Space and made bindings feel inconsistent.
2. Use is `E` and Fire is `F` by default, and the remap reliably takes effect
   in game, so `E` triggers Use rather than Fire.
3. `SDL2_MIXER_FORMATS` moved from the compile flags to the link flags, where
   linker settings belong, so MIDI music support is actually wired in.
4. `ALLOW_MEMORY_GROWTH` added so loading a large WAD at runtime does not run
   out of memory.

### Display

5. Window scaling added: the game fills the browser window, with "Crisp" and
   "Smooth" pixel-filter presets, a 4:3 or square-pixel aspect choice, a
   fullscreen button, and live switching while playing.
6. Optional build-time internal resolution setting added (`DOOM_RESX` and
   `DOOM_RESY`), default 640x400.

### Startup crash on newer toolchains

7. Pinned the Emscripten toolchain to known-good release 3.1.64 instead of
   "latest", after the newest release produced builds that crashed at startup
   in some browsers with a TextDecoder error and a blocked `file://` load.
   See "Why the toolchain is pinned".
8. Added `-s TEXTDECODER=0` and `-s ENVIRONMENT=web` to the link flags to
   remove the crashing code paths from the engine output entirely.
9. The page wraps the browser's TextDecoder so text read from growable memory
   is copied into a fixed buffer first. Even an engine build from an
   incompatible toolchain cannot crash on the "resizable ArrayBuffer" error.

### Diagnosability

10. If the engine fails to start, the page shows a readable error box with
    recovery steps instead of a silent black screen.
11. The setup screen and the browser console show a build stamp (SDK version,
    engine commit, internal resolution, and build time), so a stale cached
    page or a forgotten rebuild is easy to spot.
12. After every build, `install.sh` checks the compiled `doomgeneric.js` for
    the TextDecoder string path and for the mouse-bridge exports, and says
    clearly whether the build came out as intended.

### Mouse look, WASD, and the resolution menu (added later the same day)

13. Full mouse look: click to capture the mouse, horizontal motion turns,
    vertical motion looks up and down GZDoom style (y-shearing patched into
    the renderer), and the right mouse button shoots. Implemented as source
    patches on a pinned engine commit; see "What is patched in the engine
    source".
14. Keyboard defaults changed to WASD with A/D strafing (arrows still turn),
    with strafe reaching the engine through its classic comma and period
    strafe keys.
15. Mouse sensitivity control (setup screen and in-game bar) and an invert
    toggle.
16. Mouse motion between game tics is accumulated instead of dropped, so
    fast flicks track correctly.
17. The internal render resolution is now an interactive menu when building
    (environment variables still skip it).
18. The doomgeneric source is pinned to a fixed commit and reset before
    patching on every run, for the same reproducibility reasons the compiler
    is pinned.
19. Fixed a latent crash: the SDK's environment script clears environment
    variables named EMSDK*, which killed this script under `set -u` whenever
    `EMSDK_DIR` was overridden from the environment. The script now keeps
    the value in a name the SDK does not manage.

### Sensitivity, raw input, and left-click fire (same day, round two)

20. Horizontal and vertical mouse sensitivity are now separate settings, on
    the setup screen and the in-game bar.
21. Raw input (no mouse acceleration) added and on by default, using the
    pointer lock unadjustedMovement option, with a quiet fallback for
    browsers that refuse it.
22. The left mouse button now fires as well; the right button still fires.
    The click that captures the mouse never fires a shot, because buttons
    only reach the game while the mouse is captured.

### FPS counter and PWAD loader (same day, round three)

23. FPS counter: the engine patch counts rendered frames and exports a
    getter; the page samples it once a second and shows the number in the
    top right corner, toggleable from the in-game bar.
24. PWAD loader: an optional multi-file picker loads add-on WADs on top of
    the main WAD with the engine's `-file` option, in selection order. See
    "Loading PWADs (mods)" for the vanilla-engine caveats.
25. The post-build verification now also checks the FPS counter export.
26. Verified against the source that the BSP-based line-of-sight check from
    the 1997 source-release notes is already present in this engine
    (`P_CheckSight` in `p_sight.c` walks the BSP after a REJECT-table
    check), so nothing needed changing there. Renderer restructuring and
    GPU rendering were assessed and deliberately not attempted: both mean
    replacing the 1993 renderer rather than patching it.

### Static limit removal (same day, round four)

27. All of vanilla's map-complexity limits enlarged Doom-plus style, 8x to
    32x: visplanes, openings, drawsegs, vissprites, spechit, intercepts,
    plats, ceilings, buttons, line animations, and the emulated savegame
    size cap. Pure size bumps, no behavior changes, overrun emulations
    untouched. See item 5 under "What is patched in the engine source" for
    every value.
28. Documented that Boom-format WADs remain out of scope: limit removal
    fixes overflow crashes, not missing Boom features.

### Readable engine errors (same day, round five)

29. Fixed a WebAssembly trap in the engine's error path: a boolean-returning
    function was registered as a void exit handler through a cast
    (`d_main.c`), so every I_Error died as an opaque "function signature
    mismatch" instead of exiting cleanly. A signature-correct wrapper fixes
    it; behavior is otherwise identical.
30. The page now captures the engine's console output and shows the last
    lines in the red error box, so the engine's own explanation is visible
    without opening developer tools. A watchdog also reports the case where
    the engine stops before rendering its first frame, which is how clean
    engine errors look from the outside.
31. The setup screen detects the shareware-IWAD-plus-PWADs combination by
    reading the WAD's lump directory, and refuses with a clear warning
    before starting, instead of letting the engine refuse after the screen
    has already switched over.

### IWAD identity fix (same day, round six)

32. Fixed a page bug that made the engine treat EVERY main WAD as shareware
    Doom 1, including a real doom2.wad. The engine identifies IWADs by
    filename first (its d_iwad.c name table; contents are only inspected
    for unknown names), and the page had always presented the chosen file
    to the engine as doom1.wad. The page now derives the correct
    engine-facing name from the file's real name and its lump directory
    (doom2.wad stays doom2.wad, a full Doom misnamed doom1.wad becomes
    doom.wad, true shareware stays doom1.wad), so Doom II and Final Doom
    WADs run as themselves and accept PWADs.

### Performance (same day, round seven)

33. The engine is now compiled and linked with `-O2` plus
    `-fno-strict-aliasing`. Every earlier build ran at emcc's default of
    `-O0`, which is the single biggest reason heavy maps struggled.
34. Capped the tic catch-up loop in the engine patch: overloaded frames run
    at most 4 tics, so heavy maps go slow motion instead of freezing the
    browser tab. Single player only.
35. Zone allocator default raised from 6 MiB to 64 MiB (`-mb` still
    overrides), C stack raised to 1 MiB, initial WebAssembly memory set to
    128 MiB.
36. The FPS readout now shows game-logic speed beside render speed
    ("game: N/35"), fed by a new engine export, so slow motion and render
    slowness are distinguishable at a glance.

### Quit to menu and polish (round eight, v1.3.2)

37. Quitting from Doom's own menu ("quit to DOS") now returns to the setup
    screen instead of leaving a dead black canvas. The engine patch
    registers a quit notifier in the engine's exit-function list (clean
    quits only, never the error path) that calls a page hook; the page
    resets, keeps the WAD selections and settings, and the next press of
    Start boots a completely fresh engine instance.
38. The in-game control bar is now nearly invisible during play (barely
    there instead of half transparent); mouse over it, or focus a control
    in it, and it comes back to full strength.
39. Removed the essay about the 1997 source-release notes from this README;
    the one finding that mattered is recorded in item 26.

### DeHackEd support (round nine)

40. Full DeHackEd support: a .deh file picker on the setup screen (files
    keep their names, applied in order via `-deh`), automatic loading of
    DEHACKED lumps carried by PWADs, and automatic IWAD patches, which
    makes the HACX 1.2 standalone IWAD, Freedoom's text fixes, and Chex
    Quest (with `chex.deh` supplied) work. doomgeneric had kept all of
    Chocolate Doom's DeHackEd integration but deleted the parser; the
    engine patch re-opens the integration and `install.sh` restores the
    parser sources from Chocolate Doom 2.2.1, this fork's exact ancestor
    vintage. See item 5 under "What is patched in the engine source".

### GPU filters, free games, WAD merging, sensitivity (round ten)

41. Three GPU pixel upscalers added (hq2x, xBR, DCCI), implemented as WebGL
    shaders that redraw the frame at 2x with edge-aware interpolation onto
    an overlay canvas, with automatic fallback to Smooth when WebGL is
    unavailable. All three shaders were compiled and checked before
    shipping.
42. WAD-merge (`-merge`) support restored alongside DeHackEd, so total
    conversions load with their own graphics. See item 5 under "What is
    patched in the engine source".
43. Optional one-click free games. The installer can download a freeware
    pack (Doom shareware, Freedoom 1 and 2, HACX, Chex Quest 1 and 2,
    Harmony) and pack each file for local `file://` loading; the setup
    screen turns them into buttons. Nothing is stored in the repository.
    Chex Quest 3 is intentionally excluded as a ZDoom-only game.
44. Mouse sensitivity now has seven steps per axis (Extra low to Extra
    high), and the defaults changed to Sens X High, Sens Y Low.

### Quit to menu, actually (round eleven)

45. Fixed quit-to-menu, which round eight shipped but which never fired in
    practice. Three engine facts conspired: this platform's I_Quit RETURNS
    instead of exiting; exit functions run in reverse registration order,
    so the page notifier (registered first, at init) ran last; and the
    ENDOOM farewell-screen path, whose display is stubbed on this platform,
    still called exit() midway through the chain, killing everything after
    it, including the notifier. Fixes: the notifier now registers on the
    first rendered frame (last registered, so it runs first), ENDOOM is off
    by default (its only remaining effect here was breaking quit), and the
    notifier cancels the browser main loop so a quit game stops ticking
    behind the setup screen.

### Classic TC links and manual merge (round twelve)

46. Added a "load as total conversion (merge)" toggle to the manual PWAD
    picker, exposing the restored merge loader for any TC you supply
    yourself (this is also the intended way to run the classic WolfenDoom
    packs from the idgames archive).
47. Added read-up links on the setup screen for Aliens TC (1994) and
    Batman Doom (1999, ACE Team). Both run on this engine class, but both
    are based on film and comics properties, so they are deliberately NOT
    offered as downloads; the links go to their Doom Wiki articles so
    players can research and decide for themselves.
48. Added WolfenDoom: First Encounter to the freeware pack as a one-click
    total conversion over Freedoom Phase 2. Unlike the film and comics TCs
    above, this is a fan recreation of id's own franchise whose readme
    explicitly permits distribution with the readme included, which the
    pack honors by installing the readme alongside. Verified: single PWAD,
    Doom II based, no DeHackEd needed, decodes intact from the pack.
49. Fixed a stale-cache build break: machines that built during the brief
    period when the restored sources were fetched from Chocolate Doom
    2.3.0 kept that clone cached, and after the switch to 2.2.1 the old
    cache shipped the wrong vintage (a pointer-versus-struct compile error
    in deh_io.c). The cache is now keyed on the release tag and refreshes
    itself, and a vintage guard turns any future drift into a clear
    message instead of a compiler error.

### STRAIN and Star Wars notes (round fifteen)

50. Added STRAIN (1997, Alpha Dog Alliance) to the freeware pack as a
    one-click total conversion over Freedoom Phase 2, DeHackEd patch
    included. Verified from the archive: vanilla Doom II target, WAD and
    patch decode intact from the pack. Its terms permit free electronic
    distribution provided the text file and the entire package are
    included unmodified, so the pack stores the complete original archive
    untouched alongside the loader files.
51. Added Star Wars for Doom II (1998) to the read-up notes beside Aliens
    TC and Batman Doom: film property, so a link to its archive page
    rather than a download, by the same reasoning.

### Chex Quest done right (round sixteen)

52. Replaced the Chex Quest buttons after a user hit "R_InitTextures:
    Missing patch in texture SKINSYMB". The old approach merged the 1990s
    Chex total conversion over Freedoom Phase 1, but that TC's texture
    directory references the REAL Ultimate Doom's internal patch names,
    and Freedoom only guarantees matching texture names, not patch names,
    so the vanilla texture loader died on the first mismatch. The other
    TC stacks survive because their texture sets are self-contained.
53. The replacement is strictly better: Chex Quest 3: Vanilla Edition
    (Melodic Spaceship, 2024), a purpose-built backport of the entire Chex
    trilogy to this exact engine class, running as its own self-contained
    IWAD with its plain-DeHackEd companion patch, exactly as its readme
    prescribes for Chocolate-class engines. No base WAD, no merging, no
    patch-name mismatches possible. Verified: true IWAD with a complete
    resource set, decodes intact from the pack.

### Filters that actually filter, and server packaging (round seventeen)

54. Fixed the GPU filters looking like they did nothing. The engine always
    renders 320x200 and integer-fattens it into the frame buffer, so the
    shaders were edge-smoothing three-pixel-wide staircases, which their
    single-pixel corner rules cannot touch. The shaders now sample at the
    logical 320x200 pixel centers, recovering the true image exactly, and
    upscale that instead.
55. Each GPU filter now comes in 2x and stronger 4x (double-pass) variants:
    hq2x/hq4x, xBR 2x/4x, DCCI 2x/4x.
56. Corrected the frame-buffer menu documentation: the buffer size never
    changed rendering sharpness (the vanilla renderer is always 320x200);
    it only sets the integer enlargement factor.
57. The installer now prints the path to the downloaded freeware games,
    and gained an optional packaging step that produces a ready-to-upload
    site folder and tarball; every reference in the page is relative, so
    it is agnostic to domain names and subdirectories.
58. Clarified in the page and here that the Chex Quest Trilogy's episodes
    ARE the three games: Episode 1 is Chex Quest, Episode 2 is Chex Quest
    2, Episode 3 is Chex Quest 3.

### GPU filter performance pass (round eighteen)

59. Fixed the GPU filters dragging performance down at large frame buffer
    sizes. The cost was never the shaders: every display refresh uploaded
    the entire frame buffer (multiple megabytes, scaling with buffer size)
    through a slow copy path. The pipeline now stages the true 320x200
    image on a small canvas first (a fixed quarter-megabyte upload no
    matter the buffer size), refreshes the texture in place instead of
    reallocating, and throttles filtering to about 41 updates a second,
    just above the 35 Hz at which Doom's picture can actually change.
    Filter cost is now independent of the frame buffer setting.

### The 1997 fan page look (round nineteen)

60. Restyled the setup screen as a Doom fan page circa 1997: black void,
    diagonal-hatch backdrop, beveled gray boxes, Impact masthead with a
    flame rule, Courier controls, yellow links, badge row, and the build
    stamp dressed as a green LED hit counter. Pure CSS: id Software never
    released free fan-site art for classic Doom (verified), so no
    copyrighted assets are shipped and the page keeps working offline.
61. The setup screen's explanatory text was cut to one-liners; everything
    it used to say lives in this README (controls detail, mod loading
    rules, sensitivity and raw input notes, Chex episode mapping, filter
    descriptions).

### Consistency audit before going public (round twenty)

62. Swept the README and installer for claims that later rounds had made
    stale: the "no -merge support" caveat (merge was restored in round
    ten), the "Chex Quest 3 is deliberately absent" note (the Trilogy
    button IS the Vanilla Edition backport), the merge explanation naming
    Chex instead of Harmony/WolfenDoom/STRAIN, the scaling section still
    claiming rebuilds raise internal resolution, the installer's menu and
    warning still describing buffer size as sharpness with a crash risk,
    and the troubleshooting list numbering. Historical change-log entries
    are left as written; they describe what was true at the time.

### Native 320x200 (round twenty-one, v2.1)

63. Removed the frame buffer size option entirely. Since the vanilla
    renderer always draws 320x200, bigger buffers were only an enlarged
    copy of the same image; the engine now runs at exactly 320x200, which
    also deletes a multi-megabyte enlargement copy from every frame. All
    upscaling (display scaling, Smooth, the GPU filters) happens in the
    page from the true picture, and Smooth finally looks properly smooth
    because it blends real pixels instead of pre-fattened ones.
64. Added an 8x tier to every GPU filter (hq8x, xBR 8x, DCCI 8x): a third
    filter pass producing a 2560x1600 image, run through ping-pong
    framebuffers. Worth it on large or high-DPI displays; the 41 updates
    a second throttle keeps the cost bounded.

### Debian support, web deploy, cleanup (round twenty-three, v2.1)

65. Debian and Ubuntu are now supported alongside Fedora and RHEL. The
    script detects the distro family from /etc/os-release and branches
    the package manager (apt-get with build-essential versus dnf with
    gcc/gcc-c++), refusing clearly on unrecognized distros.
66. New optional deploy step: detect existing Apache or Nginx sites,
    pick one from a menu, and copy the build into a doomgeneric-WASM/
    subfolder with least-privilege permissions, correct per-distro
    ownership, and SELinux context on Fedora. Server configs are never
    modified. Verified end to end against a real nginx site.
67. New optional cleanup step after a successful deploy: verifies the
    deployed copy first, deletes only build artifacts, lists exactly
    what was removed, and keeps the source repo and the packaged
    tarball unless each is separately confirmed.

### Code organization (round twenty-four, v2.1.1)

68. The monolithic 3388-line `install.sh` has been split into modular
    step scripts, each under 200 lines, with a thin orchestrator at the
    top. The twelve numbered files (`01-packages.sh` through
    `12-cleanup.sh`) live in `scripts/steps/`, and shared config and
    helper functions are in `scripts/lib/common.sh`. Large generated files
    that were embedded as bash heredocs (the engine patch, the Makefile
    template, index.html, and the freeware pack downloader) are now real,
    syntax-highlightable files under `assets/`. Behavior is identical;
    this improves code readability and makes future patches easier to
    reason about and maintain.

