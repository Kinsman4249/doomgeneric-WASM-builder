[Back to README](../README.md)

# Prebuilt installers (no build required)

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

## About resolution

There is nothing to configure. The vanilla renderer always draws the game
at the original 320x200, and the build runs the engine at exactly that
size: earlier versions offered a bigger frame buffer option, but it only
produced an enlarged copy of the same image while costing memory and a
multi-megabyte copy every frame, so it was removed. All upscaling happens
in the page: the display scaling fills your window (see
[Display: scaling and pixel filters](PLAYING.md#display-scaling-and-pixel-filters)
in Playing) and the GPU filters work from the true 320x200 picture.
