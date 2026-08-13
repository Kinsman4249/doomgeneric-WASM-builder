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
   [Engine and build patches](docs/ENGINE-PATCHES.md)).
7. An optional packaging step that turns the build into a ready-to-upload
   website folder (all paths relative, works on any domain or subfolder).
8. An FPS counter, read from a frame counter inside the engine itself and
   toggleable from the in-game bar.
9. Doom-plus style limit removal: vanilla's 1994-sized static arrays are
   enlarged 8x-32x so slaughter-grade maps (huge monster counts, complex
   geometry) stop crashing, without changing gameplay behavior.
10. DeHackEd and WAD merging support, so classic total conversions load with
    their graphics intact.

## Quick start

```bash
git clone https://github.com/Kinsman4249/doomgeneric-WASM-builder.git
cd doomgeneric-WASM-builder
chmod +x install.sh
./install.sh
```

`install.sh` is idempotent and self-explanatory as it runs. See
[Building from source](docs/BUILDING.md) for prerequisites, what each step
does, and why the toolchain is pinned. If you would rather skip building
entirely, grab a ready-made installer instead: see
[Prebuilt installers](docs/INSTALLERS.md).

## Documentation

- [Building from source](docs/BUILDING.md) - how the build is organized,
  prerequisites, `install.sh` usage, and why the Emscripten toolchain is
  pinned.
- [Prebuilt installers](docs/INSTALLERS.md) - the Linux/Windows/macOS
  installers published on every release, and a note on resolution.
- [Playing](docs/PLAYING.md) - controls, mouse look, display scaling and
  pixel filters, loading PWADs and DeHackEd patches, and the one-click
  free games.
- [Engine and build patches](docs/ENGINE-PATCHES.md) - exactly what this
  repo changes in `Makefile.emscripten` and the doomgeneric engine source,
  plus performance notes.
- [Deploying](docs/DEPLOYING.md) - deploying into an existing Apache/Nginx
  site, deploying to Cloudflare Pages, and cleanup after deploying.
- [Troubleshooting](docs/TROUBLESHOOTING.md) - fixes for the errors and
  odd behaviors people actually hit.
- [CHANGELOG.md](CHANGELOG.md) - full history of changes.

## Legal note

The doomgeneric engine source, and the underlying Doom engine, is GPL licensed
code. Game data (WAD files) is separate copyrighted content. Only load a WAD you
legally own, or the freely distributable shareware `doom1.wad`.
