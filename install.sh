#!/usr/bin/env bash
#
# install.sh - Build DOOM (doomgeneric) into a single-file, no-server,
# browser-playable WebAssembly (WASM) build with:
#   - a WAD file picker (load any WAD at runtime),
#   - in-browser key remapping,
#   - display scaling that fills the browser window, with pixel-filtering
#     presets ("Crisp" for the original chunky pixels, "Smooth" for a
#     softened look), aspect-ratio choice, and a fullscreen button.
#
# INTENDED TO BE RUN INSIDE A FEDORA-BASED DISTROBOX CONTAINER.
# See README.md for how to create that container first.
#
# Safe to re-run: every step checks whether its work is already done
# before doing it again (this property is called "idempotent").
#
# ---------------------------------------------------------------------------
# A quick primer for readers new to bash:
#   - Lines starting with '#' are comments (ignored by the shell).
#   - VAR="value" sets a variable. "$VAR" reads it back.
#   - "${VAR:-default}" means "use $VAR if it is set, otherwise use default".
#   - Functions are declared as: name() { ...commands... }
#   - '&&' runs the next command only if the previous one succeeded.
# ---------------------------------------------------------------------------

# 'set -e'  : stop the whole script the moment any command fails.
# 'set -u'  : treat the use of an undefined variable as an error.
# 'set -o pipefail' : if any command in a pipe (a | b) fails, the pipe fails.
# Together these make the script fail loudly and early instead of limping on.
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override any of these by exporting the variable before
# running the script, e.g.  DOOM_RESX=960 DOOM_RESY=600 ./install.sh )
# ---------------------------------------------------------------------------

# Where the doomgeneric source code will be cloned to.
DOOMGENERIC_DIR="${DOOMGENERIC_DIR:-$HOME/doomgeneric}"

# Where the Emscripten SDK (the C-to-WASM compiler) will be installed.
EMSDK_DIR="${EMSDK_DIR:-$HOME/emsdk}"

# Which Emscripten SDK release to install. This is PINNED to a known-good
# version on purpose, instead of "latest". A brand-new SDK release broke this
# exact build in the wild: the game crashed at startup with
#   "TextDecoder ... The provided ArrayBuffer value must not be resizable"
# and the runtime attempted a load that browsers block on file:// pages
# ("Unsafe attempt to load URL file:...").
# Pinning also makes builds reproducible: the same script always produces the
# same result. Override by exporting EMSDK_VERSION if you want to experiment.
EMSDK_VERSION="${EMSDK_VERSION:-3.1.64}"

# ---- Optional internal render resolution -----------------------------------
# doomgeneric renders the game into a fixed-size pixel buffer that is baked in
# at COMPILE time (it cannot change while the game is running). The default is
# 640x400, which is the classic doomgeneric resolution.
#
# You can raise it here to render the game world at a higher internal
# resolution (crisper geometry, thinner "stair-stepping" on edges). This is
# the closest thing to "higher internal resolution" that the vanilla Doom
# renderer supports. The on-screen size is handled separately by the page,
# which scales this buffer to fit your browser window.
#
# WARNING: the original Doom software renderer has hard internal limits
# (visplanes, drawsegs, openings). Very high resolutions can overflow those
# on detailed maps and crash the game. Modest bumps (e.g. 960x600, 1280x800)
# are usually safe; go higher at your own risk. Keep the ratio close to 8:5
# (the same shape as 640x400) for the least surprises.
DOOM_RESX="${DOOM_RESX:-640}"
DOOM_RESY="${DOOM_RESY:-400}"

# ---------------------------------------------------------------------------
# Small helper functions for nicely coloured log output.
#   log()  = green  "==>" progress messages
#   warn() = yellow "!!"  warnings (non-fatal)
#   die()  = red    "FATAL:" message, then exit with a non-zero status
# ---------------------------------------------------------------------------
log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\n\033[1;33m!! \033[0m %s\n' "$1"; }
die()  { printf '\n\033[1;31mFATAL:\033[0m %s\n' "$1"; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------

# Running as root inside the container would put files under /root and mess up
# permissions on your normal user's home directory. Refuse to do that.
if [ "$(id -u)" -eq 0 ]; then
  die "Do not run this as root. Run it as your normal user inside the distrobox container."
fi

# This script installs packages with dnf (Fedora's package manager). If dnf is
# missing, you are almost certainly not in the intended Fedora container.
if ! command -v dnf >/dev/null 2>&1; then
  die "dnf not found. This script targets a Fedora-based distrobox container. See README.md."
fi

# Validate the optional resolution override: both values must be whole numbers.
# The regex ^[0-9]+$ means "one or more digits, start to finish".
if ! [[ "$DOOM_RESX" =~ ^[0-9]+$ ]] || ! [[ "$DOOM_RESY" =~ ^[0-9]+$ ]]; then
  die "DOOM_RESX and DOOM_RESY must be positive whole numbers (got '$DOOM_RESX' x '$DOOM_RESY')."
fi

# Friendly heads-up if the chosen resolution is large enough to risk crashes.
if [ "$DOOM_RESX" -gt 960 ] || [ "$DOOM_RESY" -gt 600 ]; then
  warn "Internal resolution ${DOOM_RESX}x${DOOM_RESY} is quite high."
  warn "The vanilla Doom renderer can overflow on complex maps at high resolutions and crash."
  warn "If you hit crashes, rebuild with a smaller DOOM_RESX/DOOM_RESY (default is 640x400)."
fi

log "Internal render resolution: ${DOOM_RESX}x${DOOM_RESY} (window scaling is handled in the browser)."

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
log "Checking required packages (git, make, cmake, python3, gcc, gcc-c++, patch)..."

# The tools the build needs. gcc/gcc-c++ are needed because emsdk compiles a
# few native helper tools while bootstrapping.
REQUIRED_PKGS=(git make cmake python3 gcc gcc-c++ patch)
MISSING_PKGS=()

# Build a list of packages that are NOT already installed (rpm -q checks that).
for pkg in "${REQUIRED_PKGS[@]}"; do
  rpm -q "$pkg" >/dev/null 2>&1 || MISSING_PKGS+=("$pkg")
done

# Only call the package manager if something is actually missing.
if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  log "Installing missing packages: ${MISSING_PKGS[*]}"
  # 'sudo -n true' tests whether sudo works without prompting. If it cannot,
  # we print guidance rather than hanging on a hidden password prompt.
  if ! sudo -n true 2>/dev/null; then
    warn "sudo may prompt for a password. If it fails outright, run this instead in another"
    warn "terminal, then re-run this script:"
    warn "  distrobox enter <your-container-name> --root"
    warn "  dnf install -y ${MISSING_PKGS[*]}"
  fi
  sudo dnf install -y "${MISSING_PKGS[@]}"
else
  log "All required packages already present."
fi

# ---------------------------------------------------------------------------
# 2. Emscripten SDK (the compiler that turns C into WebAssembly)
# ---------------------------------------------------------------------------
if [ ! -d "$EMSDK_DIR" ]; then
  log "Cloning emsdk into $EMSDK_DIR..."
  git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
else
  log "emsdk already cloned at $EMSDK_DIR."
fi

cd "$EMSDK_DIR"
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
source "$EMSDK_DIR/emsdk_env.sh"

# Confirm the compiler is really on PATH now; if not, stop with a clear error.
if ! command -v emcc >/dev/null 2>&1; then
  die "emcc still not on PATH after sourcing emsdk_env.sh. Something is wrong with the emsdk install."
fi
log "emcc available: $(emcc --version | head -n1)"

# Persist the emsdk environment so future shells get 'emcc' automatically.
# We append a small sourcing block to the user's shell startup files, but only
# once (the grep check makes this idempotent).
for RC in "$HOME/.bashrc" "$HOME/.bash_profile"; do
  LINE="source \"$EMSDK_DIR/emsdk_env.sh\" > /dev/null 2>&1"
  if ! grep -qF "emsdk_env.sh" "$RC" 2>/dev/null; then
    log "Adding emsdk sourcing to $RC"
    {
      echo ""
      echo "# Emscripten SDK"
      echo "if [ -f \"$EMSDK_DIR/emsdk_env.sh\" ]; then"
      echo "    $LINE"
      echo "fi"
    } >> "$RC"
  else
    log "$RC already sources emsdk_env.sh, skipping."
  fi
done

# ---------------------------------------------------------------------------
# 3. doomgeneric source
# ---------------------------------------------------------------------------
if [ ! -d "$DOOMGENERIC_DIR" ]; then
  log "Cloning doomgeneric into $DOOMGENERIC_DIR..."
  git clone https://github.com/ozkl/doomgeneric.git "$DOOMGENERIC_DIR"
else
  log "doomgeneric already cloned at $DOOMGENERIC_DIR."
fi

# All of the buildable C sources live in the inner "doomgeneric" folder.
BUILD_DIR="$DOOMGENERIC_DIR/doomgeneric"
cd "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 4. Patched Makefile.emscripten
# ---------------------------------------------------------------------------
# The upstream Makefile.emscripten is written for a native Linux build: it asks
# the HOST's "sdl2-config" for compiler flags (wrong for a WASM target) and it
# emits a default .html/.wasm/.data trio that needs a real web server. We
# replace it with a version that uses Emscripten's own bundled SDL2 ports and
# produces a single self-contained .js file that works straight from file://.
#
# The original is backed up once as Makefile.emscripten.orig.
log "Writing patched Makefile.emscripten (backs up original once)..."
if [ ! -f Makefile.emscripten.orig ]; then
  cp Makefile.emscripten Makefile.emscripten.orig
fi

# NOTE on the heredoc below:
#   cat > FILE << 'MAKEFILE_EOF' ... MAKEFILE_EOF
# writes everything between the markers verbatim into FILE. The single quotes
# around 'MAKEFILE_EOF' mean the shell does NOT touch $() or backticks inside,
# so the Makefile's own $(...) syntax is preserved exactly.
#
# IMPORTANT: the indented "recipe" lines inside a Makefile must begin with a
# real TAB character, not spaces. Keep them as tabs if you edit this file.
cat > Makefile.emscripten << 'MAKEFILE_EOF'
# -------------------------------------------------------------------------
# Makefile.emscripten - builds doomgeneric to a single .js (with the .wasm
# embedded inside it) for browser play with no web server.
# Generated by install.sh. Edit install.sh, not this file, to make changes
# stick across rebuilds.
# -------------------------------------------------------------------------

# V=1 makes the build print the full compiler command lines. Otherwise we hide
# them (VB="@" tells make to run a recipe line silently).
ifeq ($(V),1)
	VB=''
else
	VB=@
endif

# Use Emscripten's own SDL2 and SDL2_mixer ports. These flags are needed at
# BOTH compile time (for the headers) and link time (to pull in the port), so
# they appear in CFLAGS and LDFLAGS below.
SDL_FLAGS = -s USE_SDL=2 -s USE_SDL_MIXER=2

CC=emcc

# ---- Compile-time flags -------------------------------------------------
#   -DFEATURE_SOUND   : compile in doomgeneric's sound/music support.
#   $(SDL_FLAGS)      : SDL2 headers.
#   $(EXTRA_CFLAGS)   : injected by install.sh at build time. This is where the
#                       optional internal-resolution override lands, e.g.
#                       -DDOOMGENERIC_RESX=960 -DDOOMGENERIC_RESY=600
CFLAGS += -DFEATURE_SOUND $(SDL_FLAGS) $(EXTRA_CFLAGS)

# ---- Link-time flags ----------------------------------------------------
# These "-s NAME=VALUE" options are LINKER settings. They must live in LDFLAGS
# (used only when linking), NOT in CFLAGS. Putting them in CFLAGS makes emcc
# print "linker setting ignored during compilation" warnings for every source
# file and can leave features (like MIDI music) not actually wired in.
#
#   SDL2_MIXER_FORMATS=["mid"] : enable MIDI playback (Doom music is MUS which
#                                doomgeneric converts to MID, so we need this).
#   SINGLE_FILE=1              : embed the .wasm as base64 inside the .js, so
#                                there is no separate binary to fetch. This is
#                                what lets the game run over file:// with no
#                                web server.
#   FORCE_FILESYSTEM=1         : keep the virtual filesystem (FS) API linked in
#                                so the page can write a WAD into memory.
#   ALLOW_MEMORY_GROWTH=1      : let WASM memory grow on demand, so loading a
#                                large PWAD at runtime does not run out of heap.
#   ENVIRONMENT=web            : generate code for browsers only. Strips the
#                                runtime's Node.js and worker detection code,
#                                which has a history of attempting loads that
#                                browsers block on file:// pages.
#   TEXTDECODER=0              : use Emscripten's plain JavaScript string
#                                decoder instead of the browser's TextDecoder.
#                                Some browsers refuse TextDecoder on memory
#                                that can grow (a "resizable ArrayBuffer") and
#                                crash the game at startup. Doom does so little
#                                text decoding that speed is a non-issue. If
#                                you override EMSDK_VERSION to a much newer SDK
#                                and it rejects this setting, remove it here
#                                and in LDFLAGS below.
#   MODULARIZE=1 + EXPORT_NAME : expose the build as DoomModule(...) instead of
#                                dumping symbols into the global scope.
#   EXPORTED_RUNTIME_METHODS   : keep callMain (to start the game manually) and
#                                FS (to write the WAD) reachable from JS.
#   EXPORTED_FUNCTIONS=[_main] : keep the C main() reachable for callMain.
#   INVOKE_RUN=0               : do NOT auto-run main() on load; the page starts
#                                the engine itself, after the WAD is in place.
LDFLAGS += $(SDL_FLAGS) \
	-s SDL2_MIXER_FORMATS='["mid"]' \
	-s SINGLE_FILE=1 \
	-s FORCE_FILESYSTEM=1 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-s ENVIRONMENT=web \
	-s TEXTDECODER=0 \
	-s MODULARIZE=1 \
	-s EXPORT_NAME="DoomModule" \
	-s EXPORTED_RUNTIME_METHODS=['callMain','FS'] \
	-s EXPORTED_FUNCTIONS=['_main'] \
	-s INVOKE_RUN=0

# Standard C math and C libraries.
LIBS += -lm -lc

# Where object files go, and the base name of the output.
OBJDIR=build
OUTPUT=doomgeneric

# The full list of Doom engine object files to build. This matches upstream
# doomgeneric's emscripten object list (sound files included).
SRC_DOOM = dummy.o am_map.o doomdef.o doomstat.o dstrings.o d_event.o d_items.o d_iwad.o d_loop.o d_main.o d_mode.o d_net.o f_finale.o f_wipe.o g_game.o hu_lib.o hu_stuff.o info.o i_cdmus.o i_endoom.o i_joystick.o i_scale.o i_sound.o i_system.o i_timer.o memio.o m_argv.o m_bbox.o m_cheat.o m_config.o m_controls.o m_fixed.o m_menu.o m_misc.o m_random.o p_ceilng.o p_doors.o p_enemy.o p_floor.o p_inter.o p_lights.o p_map.o p_maputl.o p_mobj.o p_plats.o p_pspr.o p_saveg.o p_setup.o p_sight.o p_spec.o p_switch.o p_telept.o p_tick.o p_user.o r_bsp.o r_data.o r_draw.o r_main.o r_plane.o r_segs.o r_sky.o r_things.o sha1.o sounds.o statdump.o st_lib.o st_stuff.o s_sound.o tables.o v_video.o wi_stuff.o w_checksum.o w_file.o w_main.o w_wad.o z_zone.o w_file_stdc.o i_input.o i_video.o doomgeneric.o doomgeneric_emscripten.o mus2mid.o i_sdlmusic.o i_sdlsound.o
OBJS += $(addprefix $(OBJDIR)/, $(SRC_DOOM))

# Default target: build the game.
all:	$(OUTPUT)

# Remove all build products so the next build starts clean.
clean:
	rm -rf $(OBJDIR)
	rm -f $(OUTPUT).html
	rm -f $(OUTPUT).js
	rm -f $(OUTPUT).data
	rm -f $(OUTPUT).wasm

# Link step: combine every object file into the final doomgeneric.js.
# We deliberately output ".js" (not ".html"): once EXPORT_NAME is customized,
# Emscripten's own default HTML shell breaks, so we ship our own index.html.
$(OUTPUT):	$(OBJS)
	@echo [Linking $@]
	$(VB)$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) \
	-o $(OUTPUT).js $(LIBS)

# Make sure the object directory exists before any object is built.
$(OBJS): | $(OBJDIR)

$(OBJDIR):
	mkdir -p $(OBJDIR)

# Pattern rule: how to turn any foo.c into build/foo.o.
$(OBJDIR)/%.o:	%.c
	@echo [Compiling $<]
	$(VB)$(CC) $(CFLAGS) -c $< -o $@

# Handy debugging target: "make -f Makefile.emscripten print" lists the objects.
print:
	@echo OBJS: $(OBJS)
MAKEFILE_EOF

# ---------------------------------------------------------------------------
# 5. index.html (WAD picker + key remap UI + window scaling / filter presets)
# ---------------------------------------------------------------------------
log "Writing index.html..."

# Again, a quoted heredoc ('HTML_EOF') so nothing inside is expanded by the
# shell. The whole page is written verbatim.
cat > index.html << 'HTML_EOF'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>DOOM</title>
<style>
  /* Make the page fill the whole browser window with a black background. */
  html, body { margin: 0; height: 100%; }
  body { background: #000; color: #ddd; font-family: monospace; }

  /* The setup screen (WAD picker + key bindings) shown before the game runs. */
  #setup { max-width: 520px; margin: 48px auto; padding: 0 16px; }
  #setup h3 { margin-bottom: 6px; }
  #keybinds label { display: block; margin: 6px 0; }
  #keybinds input { width: 120px; }
  .hint { font-size: 0.85em; opacity: 0.7; }
  button { font-family: monospace; cursor: pointer; }

  /*
   * The "stage" is a full-window black box that holds the game canvas and
   * centers it. It is hidden until the game starts. Because it fills the
   * viewport (position: fixed; inset: 0), the canvas can be scaled to fill
   * as much of the window as the chosen aspect ratio allows.
   */
  #stage {
    position: fixed;
    inset: 0;                 /* top/right/bottom/left all 0 => fill window */
    background: #000;
    display: none;            /* flipped to "flex" when the game starts */
    align-items: center;      /* vertical centering of the canvas */
    justify-content: center;  /* horizontal centering of the canvas */
    overflow: hidden;
  }

  /*
   * The small control bar floating at the top of the stage. It lets you switch
   * the pixel filter, aspect ratio, and toggle fullscreen while playing.
   */
  #hud {
    position: absolute;
    top: 8px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 10;
    display: flex;
    gap: 14px;
    align-items: center;
    padding: 6px 12px;
    border-radius: 8px;
    background: rgba(0, 0, 0, 0.6);
    font-size: 13px;
    opacity: 0.5;             /* stays out of the way... */
    transition: opacity 0.15s ease;
  }
  #hud:hover { opacity: 1; }  /* ...until you move the mouse over it */
  #hud label { display: inline-flex; align-items: center; gap: 5px; }
  #hud select, #hud button { font-family: monospace; font-size: 13px; }

  /*
   * The canvas the game draws into. Its "backing store" size (the actual pixel
   * grid) is fixed by the engine (e.g. 640x400). We only change its DISPLAYED
   * size via CSS width/height from JavaScript, which is what scales it to the
   * window. The two filter presets below control how that scaling looks.
   */
  #canvas {
    display: block;
    background: #000;
    /* Size (width/height) is set from JavaScript in applyScaling(). */
  }
  /* "Crisp" preset: nearest-neighbour scaling => big, sharp original pixels. */
  #canvas.crisp { image-rendering: pixelated; }
  /* "Smooth" preset: the browser's default smoothing (bilinear) => softer. */
  #canvas.smooth { image-rendering: auto; }

  /* Fatal-error box: shown centered over the stage if the engine fails to
     start, so the failure is readable instead of a silent black screen. */
  #errbox {
    display: none;               /* flipped to "block" by showFatalError() */
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    z-index: 20;                 /* above the canvas and the control bar */
    max-width: 640px;
    padding: 14px 18px;
    border: 1px solid #a33;
    border-radius: 8px;
    background: rgba(40, 0, 0, 0.92);
    color: #f2c9c9;
    font-size: 13px;
    white-space: pre-wrap;       /* keep the message's line breaks */
  }
</style>
</head>
<body>

<!-- ==================== SETUP SCREEN ==================== -->
<div id="setup">
  <h1>DOOM in the browser</h1>

  <h3>1. Load a WAD</h3>
  <input type="file" id="wadfile" accept=".wad">
  <p class="hint">
    Use a WAD you legally own, or the freely redistributable shareware
    <code>doom1.wad</code>. Nothing is uploaded anywhere; the file stays in
    your browser.
  </p>

  <h3>2. Key bindings (physical key &rarr; Doom action)</h3>
  <div id="keybinds">
    <label>Move Forward: <input id="bind-up"    value="KeyW"></label>
    <label>Move Backward: <input id="bind-down"  value="KeyS"></label>
    <label>Turn Left: <input id="bind-left"  value="ArrowLeft"></label>
    <label>Turn Right: <input id="bind-right" value="ArrowRight"></label>
    <label>Fire: <input id="bind-fire"  value="KeyF"></label>
    <label>Use / Open (doors, switches): <input id="bind-use" value="KeyE"></label>
  </div>
  <p class="hint">
    Values are JavaScript <code>KeyboardEvent.code</code> names (for example
    <code>KeyW</code>, <code>ArrowUp</code>, <code>Space</code>,
    <code>ControlLeft</code>). Defaults: Fire is <code>F</code>, Use is
    <code>E</code>.
  </p>

  <h3>3. Display</h3>
  <p>
    <label>
      Pixel filter:
      <select id="filterMode">
        <option value="crisp" selected>Crisp (original pixels)</option>
        <option value="smooth">Smooth</option>
      </select>
    </label>
    &nbsp;&nbsp;
    <label>
      Aspect:
      <select id="aspectMode">
        <option value="4:3" selected>4:3 (original look)</option>
        <option value="square">Square pixels (fill by buffer)</option>
      </select>
    </label>
  </p>
  <p class="hint">
    You can change these at any time while playing using the bar at the top of
    the screen. "Crisp" keeps the classic chunky pixels; "Smooth" blends them.
  </p>

  <p>
    <button id="startBtn" disabled>Start DOOM</button>
  </p>

  <!-- Filled from JavaScript with the build stamp injected by install.sh.
       If this line is missing or shows an old date, the browser is showing
       a stale or cached copy of the page. -->
  <p class="hint" id="buildinfo"></p>
</div>

<!-- ==================== GAME STAGE ==================== -->
<div id="stage">
  <!-- Floating control bar (visible while playing). -->
  <div id="hud">
    <label>Filter:
      <select id="filterModeHud">
        <option value="crisp">Crisp</option>
        <option value="smooth">Smooth</option>
      </select>
    </label>
    <label>Aspect:
      <select id="aspectModeHud">
        <option value="4:3">4:3</option>
        <option value="square">Square</option>
      </select>
    </label>
    <button id="fullscreenBtn" type="button">Fullscreen</button>
  </div>

  <!-- The game canvas. tabindex="-1" lets us focus it from code. -->
  <canvas id="canvas" tabindex="-1" oncontextmenu="event.preventDefault()"></canvas>

  <!-- Shown only if the engine fails to start (see showFatalError below). -->
  <div id="errbox"></div>
</div>

<script>
/*
 * Compatibility shim, and it must run BEFORE the engine script below.
 *
 * Some engine builds ask the browser's TextDecoder to read text straight out
 * of the game's memory. When that memory is allowed to grow, some browsers
 * refuse with:
 *   TypeError: Failed to execute 'decode' on 'TextDecoder':
 *   The provided ArrayBuffer value must not be resizable
 * (Seen in the wild here: simply writing the WAD into the virtual filesystem
 * does a routine "does this file exist yet?" check, and building that check's
 * error message decodes a string from growable memory, killing startup.)
 *
 * The fix is simple: hand TextDecoder a COPY of the bytes instead, because a
 * copy lives in a plain fixed-size buffer. This wrapper does that
 * automatically, only when actually needed, and changes nothing otherwise.
 */
(function () {
  if (typeof TextDecoder === 'undefined') return; // very old browser, nothing to do
  var originalDecode = TextDecoder.prototype.decode;
  TextDecoder.prototype.decode = function (input, options) {
    if (input && ArrayBuffer.isView(input)) {
      var buf = input.buffer;
      // "resizable" (ArrayBuffer) and "growable" (SharedArrayBuffer) are true
      // when the underlying memory can change size, which is exactly what
      // decode() rejects. slice() copies the bytes into a fresh fixed buffer.
      if (buf && (buf.resizable === true || buf.growable === true)) {
        input = input.slice();
      }
    }
    return originalDecode.call(this, input, options);
  };
})();
</script>

<!-- The compiled engine. Defines the global DoomModule(...) factory. -->
<script src="doomgeneric.js"></script>

<script>
"use strict";

/* =========================================================================
 * Build stamp
 * -------------------------------------------------------------------------
 * install.sh replaces the placeholder below with the SDK version, internal
 * resolution, and build time when it writes this file. It is shown on the
 * setup screen and logged to the console, so "which build am I actually
 * running?" is always answerable at a glance. Browsers can cache file://
 * pages surprisingly hard, and a stale page looks identical to a fresh one.
 * ========================================================================= */

const BUILD_INFO = '__BUILD_INFO__';
console.log('DOOM page build: ' + BUILD_INFO);
document.getElementById('buildinfo').textContent = 'Build: ' + BUILD_INFO;

/* =========================================================================
 * State
 * ========================================================================= */

// The bytes of the WAD the user picked. Filled in by the file input handler.
let wadData = null;

// Becomes true only once the engine is actually running. The key-remap logic
// checks THIS (not which element has focus) before intercepting keys. Using a
// focus check here proved unreliable right after clicking Start, which is the
// bug that let the browser eat arrow keys / space and made bindings feel
// inconsistent. A simple "has the game started yet?" flag is reliable.
let gameStarted = false;

// Grab the elements we use more than once.
const canvas        = document.getElementById('canvas');
const stage         = document.getElementById('stage');
const startBtn      = document.getElementById('startBtn');
const filterSetup   = document.getElementById('filterMode');
const aspectSetup   = document.getElementById('aspectMode');
const filterHud     = document.getElementById('filterModeHud');
const aspectHud     = document.getElementById('aspectModeHud');
const fullscreenBtn = document.getElementById('fullscreenBtn');
const errbox        = document.getElementById('errbox');

/* =========================================================================
 * Fatal error reporting
 * -------------------------------------------------------------------------
 * If the engine fails to start, show a readable message on the page instead
 * of leaving a silent black screen (otherwise the error only appears in the
 * developer console, where most people never look).
 * ========================================================================= */

function showFatalError(err) {
  // Prefer the error's own message; fall back to stringifying whatever we got.
  const msg = (err && err.message) ? err.message : String(err);
  errbox.textContent =
    'DOOM failed to start.\n\n' +
    msg + '\n\n' +
    'If the browser console mentions TextDecoder, a resizable ArrayBuffer,\n' +
    'or an unsafe attempt to load a file:// URL, the engine was built with\n' +
    'an incompatible toolchain. Update this repo, re-run ./install.sh (it\n' +
    'pins a known-good toolchain and rebuilds cleanly), then reload this\n' +
    'page with a hard refresh (Ctrl+Shift+R).\n\n' +
    'This page build: ' + BUILD_INFO;
  errbox.style.display = 'block';
  console.error('DOOM failed to start:', err);
}

/* =========================================================================
 * WAD file picker
 * ========================================================================= */

// When the user picks a file, read it into memory and enable the Start button.
document.getElementById('wadfile').addEventListener('change', function (e) {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = function (ev) {
    // Uint8Array is a plain array of bytes, which is what the engine's virtual
    // filesystem expects.
    wadData = new Uint8Array(ev.target.result);
    startBtn.disabled = false;
  };
  reader.readAsArrayBuffer(file);
});

/* =========================================================================
 * Key remapping
 * -------------------------------------------------------------------------
 * How it works: Doom (via SDL) listens for keyboard events on the page. We
 * install our own listeners that run FIRST (capture phase). For any key the
 * user wants remapped, we cancel the real key and dispatch a synthetic event
 * for the key Doom should see instead. For keys Doom uses directly (arrows,
 * space, etc.) we simply stop the browser's default action (scrolling, etc.).
 *
 * Doom's built-in defaults (from its own input code):
 *   Left Ctrl / Right Ctrl -> Fire
 *   Space                  -> Use / Open
 *   Arrow keys             -> move / turn
 * So to make F = Fire we remap F -> ControlLeft, and to make E = Use we remap
 * E -> Space. That is why Use is E by default, and it genuinely triggers Use
 * (not Fire).
 * ========================================================================= */

// Build the "physical key -> key Doom should see" table from the input fields.
function buildRemapTable() {
  return {
    [document.getElementById('bind-up').value]:    'ArrowUp',     // move forward
    [document.getElementById('bind-down').value]:  'ArrowDown',   // move backward
    [document.getElementById('bind-left').value]:  'ArrowLeft',   // turn left
    [document.getElementById('bind-right').value]: 'ArrowRight',  // turn right
    [document.getElementById('bind-fire').value]:  'ControlLeft', // Fire
    [document.getElementById('bind-use').value]:   'Space',       // Use / Open
  };
}

// Keys Doom itself reacts to. We always cancel the browser's default action for
// these while the game is running, so (for example) the arrow keys and Space do
// not scroll the page or activate browser shortcuts.
const BASE_MANAGED_CODES = [
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'Space', 'Enter', 'Escape', 'Tab',
  'ControlLeft', 'ControlRight', 'ShiftLeft', 'ShiftRight', 'AltLeft', 'AltRight',
  'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11',
  'Minus', 'Equal',
];

function installKeyRemap(remapTable) {
  // The full set of key codes we manage: the base list, plus every physical
  // key the user bound, plus every key Doom should receive.
  const managedCodes = new Set([
    ...BASE_MANAGED_CODES,
    ...Object.keys(remapTable),
    ...Object.values(remapTable),
  ]);

  function remapEvent(e) {
    // Do nothing until the engine is running. THIS is the reliability fix:
    // we gate on gameStarted, not on document.activeElement === canvas.
    if (!gameStarted) return;

    // Ignore keys we do not manage, so normal typing elsewhere is unaffected.
    if (!managedCodes.has(e.code)) return;

    const mapped = remapTable[e.code];

    if (mapped && mapped !== e.code) {
      // This is a remapped key. Cancel the original and send Doom the
      // substitute key instead.
      e.preventDefault();
      e.stopImmediatePropagation();
      const synthetic = new KeyboardEvent(e.type, {
        code: mapped,
        key: e.key,
        bubbles: true,
        cancelable: true,
      });
      e.target.dispatchEvent(synthetic);
    } else {
      // A key Doom uses directly (or a synthetic one we just dispatched):
      // just prevent the browser's default action. Do NOT stop propagation,
      // so the event still reaches Doom's own listeners.
      e.preventDefault();
    }
  }

  // Capture phase (the "true" third argument) means our handler runs before
  // Doom's, so our substitutions are in place by the time Doom sees the event.
  document.addEventListener('keydown', remapEvent, true);
  document.addEventListener('keyup', remapEvent, true);

  // Clicking the canvas focuses it (helps some browsers route input reliably).
  canvas.addEventListener('mousedown', function () { canvas.focus(); });
}

/* =========================================================================
 * Display scaling and filtering
 * -------------------------------------------------------------------------
 * The engine renders into a fixed pixel buffer (canvas.width x canvas.height,
 * e.g. 640x400). We never change that buffer; we only change the canvas's
 * DISPLAYED size with CSS so it fills the window. The "filter" presets choose
 * how the browser scales those pixels:
 *   - Crisp  = nearest-neighbour (image-rendering: pixelated) = original look
 *   - Smooth = bilinear (image-rendering: auto)               = softened
 * ========================================================================= */

// Apply the chosen pixel filter by toggling a CSS class on the canvas.
function setFilter(mode) {
  canvas.classList.remove('crisp', 'smooth');
  canvas.classList.add(mode === 'smooth' ? 'smooth' : 'crisp');
}

// Resize the canvas (via CSS) to fit the stage while keeping the chosen aspect
// ratio. Called on start, on window resize, on fullscreen change, and whenever
// the engine changes the backing buffer size.
function applyScaling() {
  // The engine's render buffer size. Fall back to 640x400 if not set yet.
  const bufW = canvas.width  || 640;
  const bufH = canvas.height || 400;
  if (!bufW || !bufH) return;

  // How much room we have to draw into.
  const availW = stage.clientWidth;
  const availH = stage.clientHeight;
  if (!availW || !availH) return;

  // Desired display shape:
  //   "4:3"    -> classic Doom look (the original was shown at 4:3).
  //   "square" -> use the buffer's own shape (square pixels, no stretch).
  const aspectMode = aspectHud.value;
  const targetAspect = (aspectMode === '4:3') ? (4 / 3) : (bufW / bufH);

  // Fit a targetAspect rectangle inside the available box (letterboxing).
  let dispW, dispH;
  if (availW / availH > targetAspect) {
    // Window is wider than we need: height is the limiting dimension.
    dispH = availH;
    dispW = Math.round(availH * targetAspect);
  } else {
    // Window is taller/narrower: width is the limiting dimension.
    dispW = availW;
    dispH = Math.round(availW / targetAspect);
  }

  canvas.style.width  = dispW + 'px';
  canvas.style.height = dispH + 'px';
}

// Keep the two copies of each control (setup screen and in-game HUD) in sync,
// then apply the change. After using a control we blur it and refocus the
// canvas so keyboard input goes back to the game, not the dropdown.
function wireControl(setupEl, hudEl, onChange) {
  function sync(fromEl, toEl) {
    toEl.value = fromEl.value;
    onChange();
    fromEl.blur();
    if (gameStarted) canvas.focus();
  }
  setupEl.addEventListener('change', function () { sync(setupEl, hudEl); });
  hudEl.addEventListener('change',   function () { sync(hudEl, setupEl); });
}

wireControl(filterSetup, filterHud, function () { setFilter(filterHud.value); });
wireControl(aspectSetup, aspectHud, function () { applyScaling(); });

// Fullscreen toggle. We fullscreen the whole stage (not just the canvas) so the
// black letterbox background covers the screen too.
fullscreenBtn.addEventListener('click', function () {
  if (!document.fullscreenElement) {
    if (stage.requestFullscreen) stage.requestFullscreen().catch(function () {});
  } else {
    if (document.exitFullscreen) document.exitFullscreen();
  }
  // The actual resize happens in the fullscreenchange handler below.
});

// Re-fit whenever the window size or fullscreen state changes.
window.addEventListener('resize', applyScaling);
document.addEventListener('fullscreenchange', function () {
  applyScaling();
  if (gameStarted) canvas.focus();
});

// The engine sets the canvas's width/height attributes (its backing buffer)
// when it initializes, which can happen slightly after we first try to scale.
// A MutationObserver re-runs applyScaling the moment those attributes change,
// so the game is always sized correctly no matter the timing.
const sizeObserver = new MutationObserver(applyScaling);
sizeObserver.observe(canvas, { attributes: true, attributeFilter: ['width', 'height'] });

/* =========================================================================
 * Start the game
 * ========================================================================= */

startBtn.addEventListener('click', function () {
  // Lock in the key bindings the user chose.
  installKeyRemap(buildRemapTable());

  // Copy the setup-screen display choices into the in-game HUD controls.
  filterHud.value = filterSetup.value;
  aspectHud.value = aspectSetup.value;

  // Swap from the setup screen to the game stage.
  document.getElementById('setup').style.display = 'none';
  stage.style.display = 'flex';

  // Apply the initial filter (default: crisp / original pixels).
  setFilter(filterHud.value);

  // Boot the WASM engine. noInitialRun keeps main() from firing until we call
  // it, so we can write the WAD into the virtual filesystem first.
  DoomModule({ canvas: canvas, noInitialRun: true }).then(function (Module) {
    // Put the chosen WAD where the engine will look for it.
    Module.FS.writeFile('/doom1.wad', wadData);

    // From here on, intercept and remap keys.
    gameStarted = true;

    // Size the canvas once before we start (the MutationObserver will refine it
    // as soon as the engine sets its real buffer size during callMain).
    applyScaling();
    canvas.focus();

    // Start the engine. Emscripten's main loop "unwinds" the C stack by
    // throwing a sentinel value; that is expected, so we swallow it and log
    // anything unexpected.
    try {
      Module.callMain(['-iwad', '/doom1.wad']);
    } catch (err) {
      const isUnwind = (err === 'unwind') || (err && err.message === 'unwind');
      if (!isUnwind) showFatalError(err);
    }

    // Now that the engine has set the real buffer size, fit to the window.
    applyScaling();
    canvas.focus();
  }).catch(showFatalError);   // any failure while booting the engine lands here
});
</script>
</body>
</html>
HTML_EOF

# Stamp the page with build info. The heredoc above is quoted ('HTML_EOF'), so
# variables are NOT expanded inside it; we substitute the placeholder here
# instead. The stamp shows on the setup screen and in the browser console,
# which makes stale-cache and forgot-to-rebuild problems obvious at a glance.
BUILD_STAMP="emsdk ${EMSDK_VERSION}, ${DOOM_RESX}x${DOOM_RESY}, built $(date -u '+%Y-%m-%d %H:%M UTC')"
sed -i "s|__BUILD_INFO__|${BUILD_STAMP}|" index.html
log "Stamped index.html: ${BUILD_STAMP}"

# ---------------------------------------------------------------------------
# 6. Build
# ---------------------------------------------------------------------------
# We pass EXTRA_CFLAGS on the make command line so the Makefile can bake the
# chosen internal resolution into every compiled file. Passing it as a make
# variable (rather than editing the Makefile) keeps the Makefile generic and
# avoids any quoting surprises.
log "Building (emmake make -f Makefile.emscripten) at ${DOOM_RESX}x${DOOM_RESY}..."
emmake make -f Makefile.emscripten clean
emmake make -f Makefile.emscripten \
  EXTRA_CFLAGS="-DDOOMGENERIC_RESX=${DOOM_RESX} -DDOOMGENERIC_RESY=${DOOM_RESY}"

# Sanity check: the linker should have produced doomgeneric.js.
if [ ! -f "$BUILD_DIR/doomgeneric.js" ]; then
  die "Build finished but doomgeneric.js was not produced. Check the make output above."
fi

# Verify the TEXTDECODER=0 setting actually took effect: the engine output
# should not reference TextDecoder at all. If it does, the toolchain ignored
# the setting. The page's shim keeps that from crashing the game, but it is
# unexpected with the pinned toolchain, so say something.
if grep -q "TextDecoder" "$BUILD_DIR/doomgeneric.js"; then
  warn "doomgeneric.js still references TextDecoder. The page ships a shim that"
  warn "keeps this from crashing, but this is unexpected with the pinned"
  warn "toolchain. See the README troubleshooting section."
else
  log "Verified: doomgeneric.js contains no TextDecoder usage (as intended)."
fi

log "Build complete."
echo ""
echo "  $BUILD_DIR/doomgeneric.js   (engine, with the .wasm embedded inside)"
echo "  $BUILD_DIR/index.html       (the page you open to play)"
echo ""
echo "Open index.html directly in a browser (double-click it, or drag it into a"
echo "tab). No web server required."
