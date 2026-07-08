#!/usr/bin/env bash
#
# install.sh - Build DOOM (doomgeneric) into a single-file, no-server,
# browser-playable WebAssembly (WASM) build with:
#   - a WAD file picker (load any WAD at runtime),
#   - in-browser key remapping (WASD with A/D strafing by default),
#   - full mouse look (pointer lock; vertical aim patched into the engine),
#     with separate horizontal and vertical sensitivity, optional raw input
#     (no mouse acceleration), and both mouse buttons firing,
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

# Which doomgeneric commit to build. Pinned for the same reason the compiler
# is pinned (reproducible builds), and because this script patches the engine
# source for mouse look: patches are written against exactly this commit and
# would drift out of date if upstream moved underneath them.
DOOMGENERIC_COMMIT="${DOOMGENERIC_COMMIT:-dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284}"

# Where the Emscripten SDK (the C-to-WASM compiler) will be installed.
# You can still override this by exporting EMSDK_DIR before running. The
# value is kept in a differently named variable because the SDK's own
# environment script (emsdk_env.sh) manages, and can CLEAR, environment
# variables whose names start with EMSDK, which would blow this script up
# halfway through under 'set -u'.
WASM_BUILDER_EMSDK_DIR="${EMSDK_DIR:-$HOME/emsdk}"

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
#
# If neither variable is set, the script shows a small menu (see below). Set
# both to skip the menu, e.g.:  DOOM_RESX=960 DOOM_RESY=600 ./install.sh
DOOM_RESX="${DOOM_RESX:-}"
DOOM_RESY="${DOOM_RESY:-}"

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

# ---------------------------------------------------------------------------
# 0.5 Internal render resolution choice
# ---------------------------------------------------------------------------
# Ask interactively unless (a) both env vars are already set, or (b) there is
# no terminal to ask on (e.g. the script is being run by another program), in
# which case the classic default is used. '[ -t 0 ]' is bash for "is standard
# input a real terminal?".
if [ -z "$DOOM_RESX" ] || [ -z "$DOOM_RESY" ]; then
  if [ -t 0 ]; then
    echo ""
    echo "Choose the internal render resolution (how sharply the 3D world is"
    echo "drawn). The page scales it to fill your browser window either way;"
    echo "this only sets how much detail there is to scale."
    echo ""
    echo "  1) 640 x 400    classic doomgeneric look (default)"
    echo "  2) 960 x 600    sharper, still safe"
    echo "  3) 1280 x 800   much sharper, small crash risk on very complex maps"
    echo "  4) custom"
    echo ""
    read -r -p "Selection [1-4, Enter for 1]: " RES_CHOICE
    case "${RES_CHOICE:-1}" in
      1) DOOM_RESX=640;  DOOM_RESY=400 ;;
      2) DOOM_RESX=960;  DOOM_RESY=600 ;;
      3) DOOM_RESX=1280; DOOM_RESY=800 ;;
      4)
        read -r -p "Width in pixels: "  DOOM_RESX
        read -r -p "Height in pixels: " DOOM_RESY
        ;;
      *) die "Unrecognized selection '$RES_CHOICE'. Run the script again and pick 1-4." ;;
    esac
  else
    # Not interactive: fall back to the classic default quietly.
    DOOM_RESX=640
    DOOM_RESY=400
  fi
fi

# Validate the resolution: both values must be whole numbers.
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
if [ ! -d "$WASM_BUILDER_EMSDK_DIR" ]; then
  log "Cloning emsdk into $WASM_BUILDER_EMSDK_DIR..."
  git clone https://github.com/emscripten-core/emsdk.git "$WASM_BUILDER_EMSDK_DIR"
else
  log "emsdk already cloned at $WASM_BUILDER_EMSDK_DIR."
fi

cd "$WASM_BUILDER_EMSDK_DIR"
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
source "$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh"

# Confirm the compiler is really on PATH now; if not, stop with a clear error.
if ! command -v emcc >/dev/null 2>&1; then
  die "emcc still not on PATH after sourcing emsdk_env.sh. Something is wrong with the emsdk install."
fi
log "emcc available: $(emcc --version | head -n1)"

# Persist the emsdk environment so future shells get 'emcc' automatically.
# We append a small sourcing block to the user's shell startup files, but only
# once (the grep check makes this idempotent).
for RC in "$HOME/.bashrc" "$HOME/.bash_profile"; do
  LINE="source \"$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh\" > /dev/null 2>&1"
  if ! grep -qF "emsdk_env.sh" "$RC" 2>/dev/null; then
    log "Adding emsdk sourcing to $RC"
    {
      echo ""
      echo "# Emscripten SDK"
      echo "if [ -f \"$WASM_BUILDER_EMSDK_DIR/emsdk_env.sh\" ]; then"
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

# ---------------------------------------------------------------------------
# 3.5 Engine patches: mouse look, frame counter, limit removal
# ---------------------------------------------------------------------------
# The stock engine has no mouse support in its browser port, and vanilla Doom
# cannot look up and down at all. These patches add:
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
#   - DeHackEd support re-enabled: doomgeneric kept all of Chocolate
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
log "Writing engine patch (mouse look, frame counter, limit removal)..."
cat > wasm-builder-engine.patch << 'PATCH_EOF'
diff --git a/doomgeneric/d_loop.c b/doomgeneric/d_loop.c
index 1939dbd..0f3125c 100644
--- a/doomgeneric/d_loop.c
+++ b/doomgeneric/d_loop.c
@@ -762,6 +762,13 @@ void TryRunTics (void)
     if (counts < 1)
 	counts = 1;
 
+    // [WASM-builder] Never try to catch up by more than a few tics in
+    // one frame. Unbounded catch-up freezes the browser tab on heavy
+    // maps; capped catch-up is slow motion, like DOS Doom on a slow
+    // machine. Single player only.
+    if (!net_client_connected && counts > 4)
+	counts = 4;
+
     // wait for new tics if needed
 
     while (!PlayersInGame() || lowtic < gametic/ticdup + counts)
diff --git a/doomgeneric/d_main.c b/doomgeneric/d_main.c
index 9012e5f..86711fd 100644
--- a/doomgeneric/d_main.c
+++ b/doomgeneric/d_main.c
@@ -1085,7 +1085,7 @@ static void D_Endoom(void)
 	exit(0);
 }
 
-#if ORIGCODE
+#if 1   // [WASM-builder] was '#if ORIGCODE': DeHackEd support restored
 // Load dehacked patches needed for certain IWADs.
 static void LoadIwadDeh(void)
 {
@@ -1157,6 +1157,18 @@ static void LoadIwadDeh(void)
 }
 #endif
 
+// [WASM-builder] Exit functions must be exactly void(*)(void).
+// G_CheckDemoStatus returns a boolean, and vanilla registered it with a
+// cast, which x86 tolerates but WebAssembly rejects with a hard trap
+// ("function signature mismatch") the moment an exit function runs,
+// turning every engine error into an opaque crash. This tiny wrapper
+// has the right signature and simply ignores the return value, exactly
+// like the original cast pretended to.
+static void G_CheckDemoStatusAtExit(void)
+{
+    G_CheckDemoStatus();
+}
+
 //
 // D_DoomMain
 //
@@ -1165,7 +1177,7 @@ void D_DoomMain (void)
     int p;
     char file[256];
     char demolumpname[9];
-#if ORIGCODE
+#if 1   // [WASM-builder] was '#if ORIGCODE': DeHackEd support restored
     int numiwadlumps;
 #endif
 
@@ -1377,7 +1389,7 @@ void D_DoomMain (void)
 
     DEH_printf("W_Init: Init WADfiles.\n");
     D_AddFile(iwadfile);
-#if ORIGCODE
+#if 1   // [WASM-builder] was '#if ORIGCODE': DeHackEd support restored
     numiwadlumps = numlumps;
 #endif
 
@@ -1388,7 +1400,7 @@ void D_DoomMain (void)
     D_IdentifyVersion();
     InitGameVersion();
 
-#if ORIGCODE
+#if 1   // [WASM-builder] was '#if ORIGCODE': DeHackEd support restored
     //!
     // @category mod
     //
@@ -1510,7 +1522,10 @@ void D_DoomMain (void)
         printf("Playing demo %s.\n", file);
     }
 
-    I_AtExit((atexit_func_t) G_CheckDemoStatus, true);
+    // [WASM-builder] Registered through a signature-correct wrapper; see
+    // G_CheckDemoStatusAtExit above D_DoomMain for why the original
+    // cast trapped on WebAssembly.
+    I_AtExit(G_CheckDemoStatusAtExit, true);
 
     // Generate the WAD hash table.  Speed things up a bit.
     W_GenerateHashTable();
diff --git a/doomgeneric/doomfeatures.h b/doomgeneric/doomfeatures.h
index dff6936..b2e32ab 100644
--- a/doomgeneric/doomfeatures.h
+++ b/doomgeneric/doomfeatures.h
@@ -25,7 +25,10 @@
 
 // Enables dehacked support ('-deh')
 
-#undef FEATURE_DEHACKED
+// [WASM-builder] DeHackEd support enabled: install.sh restores the
+// parser implementation from Chocolate Doom 2.3.0 (this fork's exact
+// ancestor), and the engine patch re-opens the integration points.
+#define FEATURE_DEHACKED 1
 
 // Enables multiplayer support (network games)
 
diff --git a/doomgeneric/doomgeneric_emscripten.c b/doomgeneric/doomgeneric_emscripten.c
index 7076dd2..14d7054 100644
--- a/doomgeneric/doomgeneric_emscripten.c
+++ b/doomgeneric/doomgeneric_emscripten.c
@@ -3,6 +3,8 @@
 #include "doomkeys.h"
 #include "m_argv.h"
 #include "doomgeneric.h"
+#include "d_event.h"   // [WASM-builder] event_t / D_PostEvent for mouse input
+#include "i_system.h"  // [WASM-builder] I_AtExit for the quit notifier
 
 #include <stdio.h>
 #include <unistd.h>
@@ -96,6 +98,15 @@ static unsigned char convertToDoomKey(unsigned int key)
     case SDLK_MINUS:
       key = KEY_MINUS;
       break;
+    // [WASM-builder] Strafing: Doom has dedicated strafe key codes, bound to
+    // , and . on the classic keyboard layout. The web page remaps physical
+    // A and D onto Comma and Period so A/D strafe by default.
+    case SDLK_COMMA:
+      key = KEY_STRAFE_L;
+      break;
+    case SDLK_PERIOD:
+      key = KEY_STRAFE_R;
+      break;
     default:
       key = tolower(key);
       break;
@@ -139,8 +150,108 @@ static void handleKeyInput()
 }
 
 
+// ---------------------------------------------------------------------------
+// [WASM-builder] Mouse look bridge.
+//
+// The web page owns the pointer (browser pointer lock) and calls the two
+// exported functions below from JavaScript:
+//   DG_EM_MouseMove(dx, dy)     relative motion since the last call, in
+//                               browser pixels (positive dx = right,
+//                               positive dy = down, as browsers report it)
+//   DG_EM_MouseButtons(bits)    currently held buttons, already translated
+//                               to Doom's bitfield (bit 0 = fire)
+//
+// Motion accumulates here and is flushed as ONE ev_mouse event per rendered
+// frame, mirroring how the engine's own SDL backends batch mouse input.
+// Doom's ev_mouse convention: data2 = X (positive turns right), data3 = Y
+// (positive means up), so the Y axis is negated when the event is built.
+// ---------------------------------------------------------------------------
+
+static int s_MouseDeltaX = 0;
+static int s_MouseDeltaY = 0;
+static int s_MouseButtons = 0;
+static int s_MouseDirty = 0;
+
+EMSCRIPTEN_KEEPALIVE void DG_EM_MouseMove(int dx, int dy)
+{
+  s_MouseDeltaX += dx;
+  s_MouseDeltaY += dy;
+  s_MouseDirty = 1;
+}
+
+EMSCRIPTEN_KEEPALIVE void DG_EM_MouseButtons(int buttons)
+{
+  s_MouseButtons = buttons;
+  s_MouseDirty = 1;
+}
+
+static void flushMouseEvents(void)
+{
+  event_t ev;
+
+  if (!s_MouseDirty)
+  {
+    return;
+  }
+
+  ev.type = ev_mouse;
+  ev.data1 = s_MouseButtons;    // held buttons (bit 0 = fire)
+  ev.data2 = s_MouseDeltaX;     // positive = turn right
+  ev.data3 = -s_MouseDeltaY;    // Doom wants positive = up
+  ev.data4 = 0;
+
+  D_PostEvent(&ev);
+
+  s_MouseDeltaX = 0;
+  s_MouseDeltaY = 0;
+  s_MouseDirty = 0;
+}
+
+// ---------------------------------------------------------------------------
+// [WASM-builder] Rendered-frame counter.
+// DG_DrawFrame increments this once per rendered frame; the page reads it
+// through the exported getter (about once a second) to show an FPS counter.
+// A plain int is fine here: the page's JavaScript and the game run on the
+// same thread, so there is no race.
+// ---------------------------------------------------------------------------
+
+static int s_FrameCount = 0;
+
+EMSCRIPTEN_KEEPALIVE int DG_EM_GetFrameCount(void)
+{
+  return s_FrameCount;
+}
+
+// [WASM-builder] The engine's game-logic clock (35 per second at full
+// speed). The page shows tics per second beside FPS: rendering speed and
+// game-logic speed are different things, and telling them apart is the
+// whole point of a performance readout on heavy maps.
+extern int gametic;
+
+EMSCRIPTEN_KEEPALIVE int DG_EM_GetGameTic(void)
+{
+  return gametic;
+}
+
+// [WASM-builder] Runs when the player quits from Doom's own menu (the
+// engine calls its registered exit functions before stopping). EM_ASM
+// executes a snippet of JavaScript from C: here it calls a hook the page
+// installs, so the page can put its setup screen back.
+static void NotifyPageOfQuit(void)
+{
+  EM_ASM({
+    if (typeof window !== 'undefined' && window.wasmBuilderOnQuit) {
+      window.wasmBuilderOnQuit();
+    }
+  });
+}
+
 void DG_Init()
 {
+  // [WASM-builder] Fire the page's quit hook on clean quits only:
+  // run_on_error=false keeps this out of the engine-error path.
+  I_AtExit(NotifyPageOfQuit, false);
+
   window = SDL_CreateWindow("DOOM",
                             SDL_WINDOWPOS_UNDEFINED,
                             SDL_WINDOWPOS_UNDEFINED,
@@ -167,7 +278,9 @@ void DG_DrawFrame()
   SDL_RenderCopy(renderer, texture, NULL, NULL);
   SDL_RenderPresent(renderer);
 
+  s_FrameCount++;       // [WASM-builder] one more rendered frame (FPS counter)
   handleKeyInput();
+  flushMouseEvents();   // [WASM-builder] deliver this frame's mouse input
 }
 
 void DG_SleepMs(uint32_t ms)
diff --git a/doomgeneric/g_game.c b/doomgeneric/g_game.c
index 9954d78..8a7fdae 100644
--- a/doomgeneric/g_game.c
+++ b/doomgeneric/g_game.c
@@ -73,7 +73,10 @@
 #include "g_game.h"
 
 
-#define SAVEGAMESIZE	0x2c000
+// [WASM-builder limits] Vanilla: 0x2c000 (180224). Saves here are stream
+// based, but the vanilla size limit is still emulated with an I_Error
+// ("Savegame buffer overrun") past this size. x16, Doom-plus style.
+#define SAVEGAMESIZE	(0x2c000 * 16)
 
 void	G_ReadDemoTiccmd (ticcmd_t* cmd); 
 void	G_WriteDemoTiccmd (ticcmd_t* cmd); 
@@ -205,6 +208,12 @@ static boolean *mousebuttons = &mousearray[1];  // allow [-1]
 int             mousex;
 int             mousey;         
 
+// [WASM-builder mouse look] How far the view is pitched up or down, in
+// y-shear pixels at a 200-line reference screen. Positive looks up. The
+// renderer scales this to the real view height (see r_main.c).
+int             lookdir;
+#define MAXLOOKDIR 100
+
 static int      dclicktime;
 static boolean  dclickstate;
 static int      dclicks; 
@@ -534,7 +543,14 @@ void G_BuildTiccmd (ticcmd_t* cmd, int maketic)
         } 
     }
 
-    forward += mousey; 
+    // [WASM-builder mouse look] Vertical mouse motion pitches the view
+    // (see r_main.c). Classic Doom walked you forward and back instead,
+    // which nobody expects once real mouse look exists.
+    lookdir += mousey / 2;
+    if (lookdir > MAXLOOKDIR)
+	lookdir = MAXLOOKDIR;
+    else if (lookdir < -MAXLOOKDIR)
+	lookdir = -MAXLOOKDIR;
 
     if (strafe) 
 	side += mousex*2; 
@@ -662,6 +678,7 @@ void G_DoLoadLevel (void)
     memset (gamekeydown, 0, sizeof(gamekeydown));
     joyxmove = joyymove = joystrafemove = 0;
     mousex = mousey = 0;
+    lookdir = 0;   // [WASM-builder mouse look] start each level looking level
     sendpause = sendsave = paused = false;
     memset(mousearray, 0, sizeof(mousearray));
     memset(joyarray, 0, sizeof(joyarray));
@@ -827,8 +844,11 @@ boolean G_Responder (event_t* ev)
 		 
       case ev_mouse: 
         SetMouseButtons(ev->data1);
-	mousex = ev->data2*(mouseSensitivity+5)/10; 
-	mousey = ev->data3*(mouseSensitivity+5)/10; 
+	// [WASM-builder mouse look] += instead of =, so motion from several
+	// mouse events between game tics adds up instead of being dropped.
+	// G_BuildTiccmd zeroes these after it consumes them.
+	mousex += ev->data2*(mouseSensitivity+5)/10;
+	mousey += ev->data3*(mouseSensitivity+5)/10;
 	return true;    // eat events 
  
       case ev_joystick: 
diff --git a/doomgeneric/i_system.c b/doomgeneric/i_system.c
index 53ab2c9..4bfd843 100644
--- a/doomgeneric/i_system.c
+++ b/doomgeneric/i_system.c
@@ -55,7 +55,10 @@
 #include <CoreFoundation/CFUserNotification.h>
 #endif
 
-#define DEFAULT_RAM 6 /* MiB */
+// [WASM-builder] Vanilla: 6 MiB, sized for 1993. Slaughter-grade maps
+// need far more zone memory (NUTS.wad alone spawns 10000+ objects).
+// Memory is cheap in this build; -mb still overrides.
+#define DEFAULT_RAM 64 /* MiB */
 #define MIN_RAM     6  /* MiB */
 
 
diff --git a/doomgeneric/p_local.h b/doomgeneric/p_local.h
index 95fa405..9830b00 100644
--- a/doomgeneric/p_local.h
+++ b/doomgeneric/p_local.h
@@ -152,7 +152,10 @@ typedef struct
 // Extended MAXINTERCEPTS, to allow for intercepts overrun emulation.
 
 #define MAXINTERCEPTS_ORIGINAL 128
-#define MAXINTERCEPTS          (MAXINTERCEPTS_ORIGINAL + 61)
+// [WASM-builder limits] Chocolate: ORIGINAL + 61 (the 61 exists for the
+// intercepts-overrun emulation, which is untouched). Extra headroom so
+// BFG shots through slaughter hordes cannot write past the array.
+#define MAXINTERCEPTS          (MAXINTERCEPTS_ORIGINAL + 61 + 2048)
 
 extern intercept_t	intercepts[MAXINTERCEPTS];
 extern intercept_t*	intercept_p;
@@ -216,7 +219,11 @@ extern	line_t*		ceilingline;
 // We keep the original limit, to detect what variables in memory were
 // overwritten (see SpechitOverrun())
 
-#define MAXSPECIALCROSS 		20
+// [WASM-builder limits] Chocolate: 20. The write into spechit[] has no
+// bounds check, so exceeding this corrupts memory. The vanilla overrun
+// EMULATION (SpechitOverrun, keyed to MAXSPECIALCROSS_ORIGINAL) is
+// untouched; only the real storage grows.
+#define MAXSPECIALCROSS 		512
 #define MAXSPECIALCROSS_ORIGINAL	8
 
 extern	line_t*	spechit[MAXSPECIALCROSS];
diff --git a/doomgeneric/p_spec.c b/doomgeneric/p_spec.c
index 17446b5..c96d047 100644
--- a/doomgeneric/p_spec.c
+++ b/doomgeneric/p_spec.c
@@ -133,7 +133,9 @@ anim_t*		lastanim;
 //
 //      Animating line specials
 //
-#define MAXLINEANIMS            64
+// [WASM-builder limits] Vanilla: 64. Chocolate caps instead of crashing;
+// raising the cap lets big maps animate all their scrolling walls. 16x.
+#define MAXLINEANIMS            1024
 
 extern  short	numlinespecials;
 extern  line_t*	linespeciallist[MAXLINEANIMS];
diff --git a/doomgeneric/p_spec.h b/doomgeneric/p_spec.h
index a1343bf..7af0669 100644
--- a/doomgeneric/p_spec.h
+++ b/doomgeneric/p_spec.h
@@ -238,7 +238,9 @@ typedef struct
 #define MAXSWITCHES		50
 
  // 4 players, 4 buttons each at once, max.
-#define MAXBUTTONS		16
+// [WASM-builder limits] Vanilla: 16. Overflow is I_Error
+// "P_StartButton: no button slots left!". 16x.
+#define MAXBUTTONS		256
 
  // 1 second, in ticks. 
 #define BUTTONTIME      35             
@@ -300,7 +302,9 @@ typedef struct
 
 #define PLATWAIT		3
 #define PLATSPEED		FRACUNIT
-#define MAXPLATS		30
+// [WASM-builder limits] Vanilla: 30. Overflow is I_Error
+// "P_AddActivePlat: no more plats!". 512 covers slaughter maps.
+#define MAXPLATS		512
 
 
 extern plat_t*	activeplats[MAXPLATS];
@@ -512,7 +516,9 @@ typedef struct
 
 #define CEILSPEED		FRACUNIT
 #define CEILWAIT		150
-#define MAXCEILINGS		30
+// [WASM-builder limits] Vanilla: 30. Overflow silently drops ceilings
+// (they become impossible to stop). 512 covers slaughter maps.
+#define MAXCEILINGS		512
 
 extern ceiling_t*	activeceilings[MAXCEILINGS];
 
diff --git a/doomgeneric/r_defs.h b/doomgeneric/r_defs.h
index a64ac84..2d4b8f7 100644
--- a/doomgeneric/r_defs.h
+++ b/doomgeneric/r_defs.h
@@ -48,7 +48,9 @@
 #define SIL_TOP			2
 #define SIL_BOTH		3
 
-#define MAXDRAWSEGS		256
+// [WASM-builder limits] Vanilla: 256. Overflow does not crash, it makes
+// distant walls silently vanish in complex scenes. 16x.
+#define MAXDRAWSEGS		4096
 
 
 
diff --git a/doomgeneric/r_main.c b/doomgeneric/r_main.c
index 22278fe..4d09815 100644
--- a/doomgeneric/r_main.c
+++ b/doomgeneric/r_main.c
@@ -58,6 +58,13 @@ int			centery;
 
 fixed_t			centerxfrac;
 fixed_t			centeryfrac;
+
+// [WASM-builder mouse look] lookdir lives in g_game.c: pitch in y-shear
+// pixels at a 200-line reference screen, positive = up. r_shearpixels is
+// the shift applied at the current view size, shared with r_things.c so
+// the weapon sprite can be held steady on screen.
+extern int		lookdir;
+int			r_shearpixels;
 fixed_t			projection;
 
 // just for profiling purposes
@@ -851,6 +858,43 @@ void R_SetupFrame (player_t* player)
     else
 	fixedcolormap = 0;
 		
+    // [WASM-builder mouse look] Vertical look via y-shearing, the same
+    // trick Heretic and Hexen used: slide the projection horizon
+    // (centery) up or down the screen. The yslope table used by floor
+    // and ceiling rendering depends on centery, so recompute it too.
+    // Only runs when the pitch or the view size actually changed.
+    {
+	static int	cachedshear = 0;
+	static int	cachedviewheight = 0;
+	int		shear;
+	fixed_t		dy;
+
+	// Scale from the 200-line reference to the real view height, then
+	// clamp so the horizon always stays on screen with a margin.
+	shear = lookdir * viewheight / 200;
+	if (shear > viewheight/2 - 8)
+	    shear = viewheight/2 - 8;
+	else if (shear < -(viewheight/2 - 8))
+	    shear = -(viewheight/2 - 8);
+
+	if (shear != cachedshear
+	    || viewheight != cachedviewheight
+	    || centery != viewheight/2 + shear)
+	{
+	    centery = viewheight/2 + shear;
+	    centeryfrac = centery<<FRACBITS;
+	    for (i=0 ; i<viewheight ; i++)
+	    {
+		dy = ((i-centery)<<FRACBITS)+FRACUNIT/2;
+		dy = abs(dy);
+		yslope[i] = FixedDiv ( (viewwidth<<detailshift)/2*FRACUNIT, dy);
+	    }
+	    cachedshear = shear;
+	    cachedviewheight = viewheight;
+	}
+	r_shearpixels = shear;
+    }
+
     framecount++;
     validcount++;
 }
diff --git a/doomgeneric/r_plane.c b/doomgeneric/r_plane.c
index ea1611c..f02763b 100644
--- a/doomgeneric/r_plane.c
+++ b/doomgeneric/r_plane.c
@@ -42,14 +42,18 @@ planefunction_t		ceilingfunc;
 //
 
 // Here comes the obnoxious "visplane".
-#define MAXVISPLANES	128
+// [WASM-builder limits] Vanilla: 128. The classic slaughter-map killer:
+// I_Error "R_FindPlane: no more visplanes". 32x.
+#define MAXVISPLANES	4096
 visplane_t		visplanes[MAXVISPLANES];
 visplane_t*		lastvisplane;
 visplane_t*		floorplane;
 visplane_t*		ceilingplane;
 
 // ?
-#define MAXOPENINGS	SCREENWIDTH*64
+// [WASM-builder limits] Vanilla: SCREENWIDTH*64. Complex scenes need
+// more clip-window openings; overflow here corrupts memory. x8.
+#define MAXOPENINGS	SCREENWIDTH*64*8
 short			openings[MAXOPENINGS];
 short*			lastopening;
 
diff --git a/doomgeneric/r_things.c b/doomgeneric/r_things.c
index 74e7369..c2cfed1 100644
--- a/doomgeneric/r_things.c
+++ b/doomgeneric/r_things.c
@@ -685,6 +685,15 @@ void R_DrawPSprite (pspdef_t* psp)
     vis = &avis;
     vis->mobjflags = 0;
     vis->texturemid = (BASEYCENTER<<FRACBITS)+FRACUNIT/2-(psp->sy-spritetopoffset[lump]);
+
+    // [WASM-builder mouse look] The view shear moves centery, which would
+    // drag the weapon sprite up and down the screen with it. Shift the
+    // sprite the opposite way so it stays put (weapon bob still applies).
+    {
+	extern int r_shearpixels;
+	vis->texturemid += FixedDiv(r_shearpixels<<FRACBITS,
+				    pspritescale<<detailshift);
+    }
     vis->x1 = x1 < 0 ? 0 : x1;
     vis->x2 = x2 >= viewwidth ? viewwidth-1 : x2;	
     vis->scale = pspritescale<<detailshift;
diff --git a/doomgeneric/r_things.h b/doomgeneric/r_things.h
index 256a5eb..9a1c951 100644
--- a/doomgeneric/r_things.h
+++ b/doomgeneric/r_things.h
@@ -22,7 +22,10 @@
 
 
 
-#define MAXVISSPRITES  	128
+// [WASM-builder limits] Vanilla: 128. Overflow does not crash (a dummy
+// overflow sprite is returned) but monsters beyond the limit are not
+// drawn, which defeats slaughter-map testing. 16x.
+#define MAXVISSPRITES  	2048
 
 extern vissprite_t	vissprites[MAXVISSPRITES];
 extern vissprite_t*	vissprite_p;
PATCH_EOF

log "Applying engine patch..."
patch -p1 < wasm-builder-engine.patch

# ---------------------------------------------------------------------------
# 3.6 DeHackEd parser sources (from Chocolate Doom)
# ---------------------------------------------------------------------------
# doomgeneric descends from Chocolate Doom but deleted the DeHackEd parser
# implementation files (only the headers and the integration code remain).
# DeHackEd patches (.deh) are how classic mods change monster behavior,
# weapon stats, and text: HACX, Chex Quest, Freedoom, and countless mods
# rely on them. We restore the implementation from Chocolate Doom at the
# exact release this fork descends from (verified: the deh headers that
# remain in doomgeneric are byte-identical to that release), so the files
# drop straight in. Pinned to a tag for reproducibility, cached like the
# other clones, re-copied on every run so the result is always consistent.
CHOCO_TAG="chocolate-doom-2.3.0"
CHOCO_DIR="$DOOMGENERIC_DIR/chocolate-deh-src"
if [ ! -d "$CHOCO_DIR" ]; then
  log "Fetching the DeHackEd implementation (Chocolate Doom $CHOCO_TAG)..."
  git clone --quiet --depth 1 --branch "$CHOCO_TAG" \
    https://github.com/chocolate-doom/chocolate-doom.git "$CHOCO_DIR"
else
  log "Chocolate Doom sources already fetched at $CHOCO_DIR."
fi

log "Installing DeHackEd parser sources into the engine..."
# Shared parser core (the three deh headers already in doomgeneric are kept).
cp "$CHOCO_DIR/src/deh_defs.h" "$CHOCO_DIR/src/deh_io.h" \
   "$CHOCO_DIR/src/deh_mapping.h" "$CHOCO_DIR/src/deh_io.c" \
   "$CHOCO_DIR/src/deh_main.c" "$CHOCO_DIR/src/deh_mapping.c" \
   "$CHOCO_DIR/src/deh_str.c" "$CHOCO_DIR/src/deh_text.c" doomgeneric/
# Doom-specific section parsers (things, frames, weapons, ammo, cheats...).
cp "$CHOCO_DIR"/src/doom/deh_*.c doomgeneric/

# One-line adaptation: this engine's WAD directory is an array of structs,
# while that Chocolate release used an array of pointers.
sed -i 's/lumpinfo\[lumpnum\]->name/lumpinfo[lumpnum].name/' doomgeneric/deh_io.c

# All of the buildable C sources live in the inner "doomgeneric" folder.
BUILD_DIR="$DOOMGENERIC_DIR/doomgeneric"
cd "$BUILD_DIR"

# Sanity: the DeHackEd sources must be in place before the build.
if [ ! -f deh_main.c ] || [ ! -f deh_defs.h ]; then
  die "DeHackEd sources missing after the copy step. Check the Chocolate Doom clone at $CHOCO_DIR."
fi

# ---------------------------------------------------------------------------
# 4. Patched Makefile.emscripten
# ---------------------------------------------------------------------------
# The upstream Makefile.emscripten is written for a native Linux build: it asks
# the HOST's "sdl2-config" for compiler flags (wrong for a WASM target) and it
# emits a default .html/.wasm/.data trio that needs a real web server. We
# replace it with a version that uses Emscripten's own bundled SDL2 ports and
# produces a single self-contained .js file that works straight from file://.
#
# (No backup file is needed: the git reset above already restored the
# pristine upstream Makefile before this rewrite, every run.)
log "Writing patched Makefile.emscripten..."

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
#   -O2                    : optimize. Without this, emcc compiles at -O0
#                            (no optimization at all), which is 5-20x slower
#                            at runtime; heavy maps were freezing largely
#                            because of it.
#   -fno-strict-aliasing   : 1993 C plays loose with pointer types in a few
#                            places; this tells the optimizer not to assume
#                            otherwise. Standard practice for Doom ports.
#   -DFEATURE_SOUND        : compile in doomgeneric's sound/music support.
#   $(SDL_FLAGS)           : SDL2 headers.
#   $(EXTRA_CFLAGS)        : injected by install.sh at build time (the
#                            internal-resolution override lands here).
CFLAGS += -O2 -fno-strict-aliasing -DFEATURE_SOUND $(SDL_FLAGS) $(EXTRA_CFLAGS)

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
#   EXPORTED_FUNCTIONS         : keep the C main() reachable for callMain, and
#                                the two mouse-bridge functions the page calls
#                                for mouse look (see the engine patches).
#   INVOKE_RUN=0               : do NOT auto-run main() on load; the page starts
#                                the engine itself, after the WAD is in place.
#   -O2 (at link)              : REQUIRED at link time too with Emscripten:
#                                this is where the WebAssembly optimizer
#                                (wasm-opt) and JS minification run.
#   STACK_SIZE=1048576         : 1 MiB C stack (the modern emcc default is a
#                                slim 64 KiB, and the renderer's recursive
#                                BSP walk on huge maps wants headroom).
#   INITIAL_MEMORY=134217728   : start with 128 MiB so the enlarged engine
#                                limits and big WADs do not trigger repeated
#                                memory-growth pauses mid game.
LDFLAGS += $(SDL_FLAGS) \
	-O2 \
	-s STACK_SIZE=1048576 \
	-s INITIAL_MEMORY=134217728 \
	-s SDL2_MIXER_FORMATS='["mid"]' \
	-s SINGLE_FILE=1 \
	-s FORCE_FILESYSTEM=1 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-s ENVIRONMENT=web \
	-s TEXTDECODER=0 \
	-s MODULARIZE=1 \
	-s EXPORT_NAME="DoomModule" \
	-s EXPORTED_RUNTIME_METHODS=['callMain','FS'] \
	-s EXPORTED_FUNCTIONS=['_main','_DG_EM_MouseMove','_DG_EM_MouseButtons','_DG_EM_GetFrameCount','_DG_EM_GetGameTic'] \
	-s INVOKE_RUN=0

# Standard C math and C libraries.
LIBS += -lm -lc

# Where object files go, and the base name of the output.
OBJDIR=build
OUTPUT=doomgeneric

# The full list of Doom engine object files to build: upstream doomgeneric's
# emscripten object list (sound included), plus the DeHackEd parser sources
# restored from Chocolate Doom (the deh_*.o entries at the end).
SRC_DOOM = dummy.o am_map.o doomdef.o doomstat.o dstrings.o d_event.o d_items.o d_iwad.o d_loop.o d_main.o d_mode.o d_net.o f_finale.o f_wipe.o g_game.o hu_lib.o hu_stuff.o info.o i_cdmus.o i_endoom.o i_joystick.o i_scale.o i_sound.o i_system.o i_timer.o memio.o m_argv.o m_bbox.o m_cheat.o m_config.o m_controls.o m_fixed.o m_menu.o m_misc.o m_random.o p_ceilng.o p_doors.o p_enemy.o p_floor.o p_inter.o p_lights.o p_map.o p_maputl.o p_mobj.o p_plats.o p_pspr.o p_saveg.o p_setup.o p_sight.o p_spec.o p_switch.o p_telept.o p_tick.o p_user.o r_bsp.o r_data.o r_draw.o r_main.o r_plane.o r_segs.o r_sky.o r_things.o sha1.o sounds.o statdump.o st_lib.o st_stuff.o s_sound.o tables.o v_video.o wi_stuff.o w_checksum.o w_file.o w_main.o w_wad.o z_zone.o w_file_stdc.o i_input.o i_video.o doomgeneric.o doomgeneric_emscripten.o mus2mid.o i_sdlmusic.o i_sdlsound.o deh_ammo.o deh_bexstr.o deh_cheat.o deh_doom.o deh_frame.o deh_io.o deh_main.o deh_mapping.o deh_misc.o deh_ptr.o deh_sound.o deh_str.o deh_text.o deh_thing.o deh_weapon.o
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
  /* Setup-screen warning (for example shareware WAD + PWADs selected). */
  #setupwarn {
    display: none;               /* shown from JavaScript when relevant */
    padding: 8px 12px;
    border: 1px solid #a33;
    border-radius: 6px;
    background: rgba(60, 10, 10, 0.5);
    color: #f2b8b8;
    font-size: 0.9em;
  }
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
    opacity: 0.07;            /* nearly invisible during play... */
    transition: opacity 0.15s ease;
  }
  /* ...until the mouse is over it (or a control in it has focus). */
  #hud:hover, #hud:focus-within { opacity: 1; }
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

  /* FPS readout, top-right corner. Shown while the HUD's FPS box is
     checked. The number is rendered frames per second, sampled once a
     second from a counter inside the engine itself. */
  #fpsbox {
    display: none;               /* toggled from JavaScript */
    position: absolute;
    top: 8px;
    right: 10px;
    z-index: 10;
    padding: 4px 8px;
    border-radius: 6px;
    background: rgba(0, 0, 0, 0.6);
    color: #8f8;
    font-size: 13px;
  }

  /*
   * Mouse-capture hint: shown at the bottom of the stage while the game is
   * running but the mouse is not captured (pointer lock not active). Hidden
   * automatically the moment the mouse is captured.
   */
  #mousehint {
    display: none;               /* toggled from JavaScript */
    position: absolute;
    bottom: 14px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 10;
    padding: 6px 12px;
    border-radius: 8px;
    background: rgba(0, 0, 0, 0.65);
    color: #cfc;
    font-size: 13px;
    white-space: nowrap;
  }

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
  <p>
    <label>Optional PWADs (mods, maps): <input type="file" id="pwadfiles" accept=".wad" multiple></label>
  </p>
  <p class="hint">
    PWADs load on top of the main WAD (the engine's <code>-file</code>
    option), in the order selected. They need a full IWAD: the shareware
    <code>doom1.wad</code> refuses add-on files by design. This engine uses
    the plain vanilla loader, so PWADs that replace sprites or floor
    textures may not show those replacements. PWADs that carry a DEHACKED
    lump have it applied automatically.
  </p>
  <p>
    <label>Optional DeHackEd patches (.deh): <input type="file" id="dehfiles" accept=".deh,.bex" multiple></label>
  </p>
  <p class="hint">
    DeHackEd patches change monster behavior, weapon stats, and text; many
    classic mods ship one next to their PWAD. Applied in selection order
    with the engine's <code>-deh</code> option, after the main WAD's own
    patch and before PWAD DEHACKED lumps, matching classic load order.
    Files keep their names, so Chex Quest's required patch works if the
    file is named <code>chex.deh</code>. The HACX 1.2 IWAD needs nothing
    here; its built-in patch loads by itself.
  </p>

  <h3>2. Controls</h3>
  <p class="hint">
    The mouse turns and looks up/down once you click the game to capture it
    (Esc releases it). <b>Both mouse buttons shoot.</b> Keyboard defaults:
    WASD movement with A/D strafing (the mouse covers turning), F also
    shoots, E opens doors and presses switches.
  </p>
  <div id="keybinds">
    <label>Move Forward: <input id="bind-up"     value="KeyW"></label>
    <label>Move Backward: <input id="bind-down"   value="KeyS"></label>
    <label>Strafe Left: <input id="bind-sleft"  value="KeyA"></label>
    <label>Strafe Right: <input id="bind-sright" value="KeyD"></label>
    <label>Turn Left: <input id="bind-left"   value="ArrowLeft"></label>
    <label>Turn Right: <input id="bind-right"  value="ArrowRight"></label>
    <label>Fire: <input id="bind-fire"   value="KeyF"></label>
    <label>Use / Open (doors, switches): <input id="bind-use" value="KeyE"></label>
  </div>
  <p class="hint">
    Values are JavaScript <code>KeyboardEvent.code</code> names (for example
    <code>KeyW</code>, <code>ArrowUp</code>, <code>Space</code>,
    <code>ControlLeft</code>).
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
  <p>
    <label>
      Horizontal sensitivity:
      <select id="sensXMode">
        <option value="0.5">Low</option>
        <option value="1" selected>Normal</option>
        <option value="1.5">High</option>
        <option value="2">Higher</option>
        <option value="3">Very high</option>
      </select>
    </label>
    &nbsp;&nbsp;
    <label>
      Vertical sensitivity:
      <select id="sensYMode">
        <option value="0.5">Low</option>
        <option value="1" selected>Normal</option>
        <option value="1.5">High</option>
        <option value="2">Higher</option>
        <option value="3">Very high</option>
      </select>
    </label>
  </p>
  <p>
    <label>
      <input type="checkbox" id="rawInput" checked> Raw input (disable mouse acceleration)
    </label>
    &nbsp;&nbsp;
    <label>
      <input type="checkbox" id="invertLook"> Invert mouse look
    </label>
  </p>
  <p class="hint">
    Raw input asks the browser for unaccelerated mouse motion, so a flick of
    the wrist moves the same amount no matter how fast you flick. Not every
    browser supports it; if yours refuses, the game quietly falls back to
    normal (accelerated) motion. Changing it takes effect the next time you
    capture the mouse.
  </p>
  <p class="hint">
    You can change filter, aspect, and sensitivity at any time while playing
    using the bar at the top of the screen (press Esc first to free the
    mouse). "Crisp" keeps the classic chunky pixels; "Smooth" blends them.
  </p>

  <!-- Shown when the current WAD selection cannot start (see JavaScript). -->
  <p id="setupwarn"></p>

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
    <label>Sens X:
      <select id="sensXModeHud">
        <option value="0.5">Low</option>
        <option value="1">Normal</option>
        <option value="1.5">High</option>
        <option value="2">Higher</option>
        <option value="3">Very high</option>
      </select>
    </label>
    <label>Sens Y:
      <select id="sensYModeHud">
        <option value="0.5">Low</option>
        <option value="1">Normal</option>
        <option value="1.5">High</option>
        <option value="2">Higher</option>
        <option value="3">Very high</option>
      </select>
    </label>
    <label><input type="checkbox" id="fpsToggle" checked> FPS</label>
    <button id="fullscreenBtn" type="button">Fullscreen</button>
  </div>

  <!-- FPS readout (top-right), fed by a frame counter inside the engine. -->
  <div id="fpsbox">FPS: --</div>

  <!-- Shown while the game runs without the mouse captured. -->
  <div id="mousehint">Click the game to capture the mouse. Mouse looks around, mouse buttons shoot, Esc releases the mouse.</div>

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
const sensXSetup    = document.getElementById('sensXMode');
const sensXHud      = document.getElementById('sensXModeHud');
const sensYSetup    = document.getElementById('sensYMode');
const sensYHud      = document.getElementById('sensYModeHud');
const rawInput      = document.getElementById('rawInput');
const invertLook    = document.getElementById('invertLook');
const mousehint     = document.getElementById('mousehint');
const fullscreenBtn = document.getElementById('fullscreenBtn');
const fpsToggle     = document.getElementById('fpsToggle');
const fpsbox        = document.getElementById('fpsbox');
const errbox        = document.getElementById('errbox');

// Filled in once the engine has booted; the mouse handlers need it to call
// the two C bridge functions the engine exports.
let doomModule = null;

/* =========================================================================
 * Engine console capture
 * -------------------------------------------------------------------------
 * Everything the engine prints (its startup log, and crucially its ERROR
 * messages) is captured into a small ring buffer, as well as mirrored to
 * the browser console. When something goes wrong, the last few lines are
 * shown in the on-page error box, so the engine's own explanation (for
 * example "You cannot -file with the shareware version") is visible without
 * opening developer tools.
 * ========================================================================= */

const engineLog = [];

function engineLogPush(text) {
  engineLog.push(String(text));
  if (engineLog.length > 40) engineLog.shift();   // keep only the tail
}

/* =========================================================================
 * Fatal error reporting
 * -------------------------------------------------------------------------
 * If the engine fails to start, show a readable message on the page instead
 * of leaving a silent black screen (otherwise the error only appears in the
 * developer console, where most people never look).
 * ========================================================================= */

function showFatalError(err) {
  // Prefer the error's own message; fall back to stringifying whatever we got.
  let msg = (err && err.message) ? err.message : String(err);

  // The engine's own last words usually explain the failure far better than
  // a JavaScript exception does, so show them front and center.
  const tail = engineLog.filter(function (l) { return l && l.trim(); }).slice(-6);
  if (tail.length > 0) {
    msg += '\n\nEngine output:\n' + tail.join('\n');
  }

  errbox.textContent =
    'DOOM failed to start.\n\n' +
    msg + '\n\n' +
    'If the engine output above names the problem (for example a WAD it\n' +
    'refuses to load), fix that and reload the page. If instead the console\n' +
    'mentions TextDecoder, a resizable ArrayBuffer, or an unsafe attempt to\n' +
    'load a file:// URL, the engine was built with an incompatible\n' +
    'toolchain: update this repo, re-run ./install.sh, then reload with a\n' +
    'hard refresh (Ctrl+Shift+R).\n\n' +
    'This page build: ' + BUILD_INFO;
  errbox.style.display = 'block';
  console.error('DOOM failed to start:', err);
}

/* =========================================================================
 * WAD file picker
 * ========================================================================= */

// Read just enough of a WAD to list its lump names. A WAD starts with a
// 12-byte header (4-byte magic, lump count, directory offset); the
// directory holds one 16-byte entry per lump with an 8-byte name. This is
// how every Doom engine identifies what a WAD contains.
function wadLumpNames(bytes) {
  if (!bytes || bytes.length < 12) return null;
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
  if (magic !== 'IWAD' && magic !== 'PWAD') return null;
  const numLumps = dv.getInt32(4, true);
  const dirOfs = dv.getInt32(8, true);
  const names = new Set();
  for (let i = 0; i < numLumps; i++) {
    const entry = dirOfs + i * 16;
    if (entry + 16 > bytes.length) break;   // truncated file: stop safely
    let name = '';
    for (let j = 0; j < 8; j++) {
      const c = bytes[entry + 8 + j];
      if (c === 0) break;
      name += String.fromCharCode(c);
    }
    names.add(name.toUpperCase());
  }
  return names;
}

// Decide what filename the engine should see for the chosen IWAD. This
// matters more than it sounds: the engine identifies IWADs by FILENAME
// first (doom2.wad means Doom II, doom1.wad means shareware, and so on,
// from its own name table in d_iwad.c) and only inspects the contents for
// names it does not recognize. Older versions of this page presented every
// file as doom1.wad, which made the engine treat even a real doom2.wad as
// shareware Doom 1 and refuse PWADs with it.
function chooseIwadName(realName, bytes) {
  const names = wadLumpNames(bytes) || new Set();
  const base = String(realName || '').toLowerCase().replace(/[^a-z0-9._-]/g, '_');

  // Filenames this Doom engine knows (from its d_iwad.c table).
  const known = ['doom2.wad', 'plutonia.wad', 'tnt.wad', 'doom.wad',
                 'doom1.wad', 'chex.wad', 'hacx.wad', 'freedm.wad',
                 'freedoom2.wad', 'freedoom1.wad'];

  // What the contents say it is: MAP01 means a Doom II style WAD, episode
  // lumps beyond E1 mean full Doom 1, episode 1 only means shareware.
  const contentName = names.has('MAP01') ? 'doom2.wad'
    : (names.has('E2M1') || names.has('E3M1') || names.has('E4M1')) ? 'doom.wad'
    : 'doom1.wad';

  if (known.indexOf(base) !== -1) {
    // Trust a recognized filename, except a full WAD misnamed doom1.wad,
    // which the engine would wrongly treat as shareware.
    if (base === 'doom1.wad' && contentName !== 'doom1.wad') return contentName;
    return base;
  }
  return contentName;
}

// Will the engine treat this IWAD as shareware? It refuses PWADs with
// shareware (by design, since 1993). The engine picks the game MODE from
// the episode lumps: Doom 1 family WADs without E3M1 or E4M1 run as
// shareware. Doom II family WADs are never shareware.
function engineWillTreatAsShareware(iwadName, bytes) {
  const names = wadLumpNames(bytes) || new Set();
  const doom2Family = ['doom2.wad', 'plutonia.wad', 'tnt.wad', 'hacx.wad',
                       'freedm.wad', 'freedoom2.wad'];
  if (doom2Family.indexOf(iwadName) !== -1 || names.has('MAP01')) return false;
  return !names.has('E3M1') && !names.has('E4M1');
}

// The engine-facing name and shareware status of the chosen main WAD.
let iwadName = 'doom.wad';
let wadIsShareware = false;

// Show or clear the setup-screen warning about shareware + PWADs. Returns
// true when the current selection cannot start.
function updateSetupWarning() {
  const warnEl = document.getElementById('setupwarn');
  const anyPwads = pwadData.some(function (p) { return p; });
  if (wadIsShareware && anyPwads) {
    warnEl.textContent =
      'The selected main WAD is identified as shareware (episode 1 only, ' +
      'no E3M1 or E4M1 maps), and the engine refuses add-on files with it ' +
      '(a vanilla rule, not a bug). Pick a full IWAD such as doom.wad, ' +
      'doom2.wad, or Freedoom, or clear the PWAD selection.';
    warnEl.style.display = 'block';
    return true;
  }
  warnEl.style.display = 'none';
  return false;
}

// When the user picks a file, read it into memory and enable the Start button.
document.getElementById('wadfile').addEventListener('change', function (e) {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = function (ev) {
    // Uint8Array is a plain array of bytes, which is what the engine's virtual
    // filesystem expects.
    wadData = new Uint8Array(ev.target.result);
    iwadName = chooseIwadName(file.name, wadData);
    wadIsShareware = engineWillTreatAsShareware(iwadName, wadData);
    console.log('IWAD will be presented to the engine as: ' + iwadName
                + (wadIsShareware ? ' (shareware)' : ''));
    updateSetupWarning();
    startBtn.disabled = false;
  };
  reader.readAsArrayBuffer(file);
});

// Optional PWADs (add-on mods and maps). Each selected file is read into
// memory here and handed to the engine with the -file option at start.
// Entries are indexed so the load order matches the selection order even
// though the files finish reading at different times.
let pwadData = [];   // array of { name, bytes }

document.getElementById('pwadfiles').addEventListener('change', function (e) {
  const files = Array.from(e.target.files || []);
  pwadData = [];
  files.forEach(function (file, index) {
    const reader = new FileReader();
    reader.onload = function (ev) {
      const bytes = new Uint8Array(ev.target.result);
      const lumps = wadLumpNames(bytes);
      pwadData[index] = {
        // A simple, safe name for the virtual filesystem; the engine only
        // cares about the WAD's contents, not its filename.
        name: 'pwad_' + index + '.wad',
        bytes: bytes,
        // Remember whether this PWAD carries a DeHackEd patch as a lump;
        // if any loaded PWAD does, the engine is started with -dehlump so
        // those patches actually apply.
        hasDehacked: !!(lumps && lumps.has('DEHACKED')),
      };
      updateSetupWarning();
    };
    reader.readAsArrayBuffer(file);
  });
  updateSetupWarning();
});

// Optional DeHackEd patch files (.deh / .bex). Unlike PWADs these KEEP
// their real filenames in the virtual filesystem: the engine looks for
// specific names in one case (Chex Quest wants chex.deh next to the IWAD).
let dehData = [];   // array of { name, bytes }

document.getElementById('dehfiles').addEventListener('change', function (e) {
  const files = Array.from(e.target.files || []);
  dehData = [];
  const usedNames = new Set();
  files.forEach(function (file, index) {
    const reader = new FileReader();
    // Sanitize but preserve the real name; deduplicate collisions.
    let name = String(file.name || 'patch.deh').toLowerCase()
                 .replace(/[^a-z0-9._-]/g, '_');
    if (usedNames.has(name)) name = index + '_' + name;
    usedNames.add(name);
    reader.onload = function (ev) {
      dehData[index] = { name: name, bytes: new Uint8Array(ev.target.result) };
    };
    reader.readAsArrayBuffer(file);
  });
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

// Build the "physical key -> key Doom should see" table from the input
// fields. The right-hand values are the keys the ENGINE understands:
// arrows move and turn, Comma and Period strafe (Doom's classic , and .
// strafe keys, wired up in the engine's browser layer), Ctrl fires, Space
// uses. Identity mappings (like ArrowLeft to ArrowLeft) are fine: the key
// passes through, and the browser's default action still gets cancelled.
function buildRemapTable() {
  return {
    [document.getElementById('bind-up').value]:     'ArrowUp',     // move forward
    [document.getElementById('bind-down').value]:   'ArrowDown',   // move backward
    [document.getElementById('bind-sleft').value]:  'Comma',       // strafe left
    [document.getElementById('bind-sright').value]: 'Period',      // strafe right
    [document.getElementById('bind-left').value]:   'ArrowLeft',   // turn left
    [document.getElementById('bind-right').value]:  'ArrowRight',  // turn right
    [document.getElementById('bind-fire').value]:   'ControlLeft', // Fire
    [document.getElementById('bind-use').value]:    'Space',       // Use / Open
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

// The active bindings. Kept in outer variables (not captured in a closure)
// so that starting the game again after a quit refreshes the bindings
// without stacking duplicate event listeners.
let activeRemapTable = null;
let activeManagedCodes = null;
let remapListenersInstalled = false;

function installKeyRemap(remapTable) {
  activeRemapTable = remapTable;
  // The full set of key codes we manage: the base list, plus every physical
  // key the user bound, plus every key Doom should receive.
  activeManagedCodes = new Set([
    ...BASE_MANAGED_CODES,
    ...Object.keys(remapTable),
    ...Object.values(remapTable),
  ]);

  // The listeners themselves are installed exactly once per page load.
  if (remapListenersInstalled) return;
  remapListenersInstalled = true;

  function remapEvent(e) {
    // Do nothing until the engine is running. THIS is the reliability fix:
    // we gate on gameStarted, not on document.activeElement === canvas.
    if (!gameStarted) return;

    // Ignore keys we do not manage, so normal typing elsewhere is unaffected.
    if (!activeManagedCodes.has(e.code)) return;

    const mapped = activeRemapTable[e.code];

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

  // Clicking the canvas focuses it (helps some browsers route input
  // reliably) and captures the mouse for mouse look. Any button works as
  // the capture click; buttons only reach the game while captured.
  canvas.addEventListener('mousedown', function () {
    canvas.focus();
    if (gameStarted && document.pointerLockElement !== canvas) {
      captureMouse();
    }
  });
}

/* =========================================================================
 * Mouse look (pointer lock)
 * -------------------------------------------------------------------------
 * Clicking the game "captures" the mouse using the browser's pointer lock,
 * the same mechanism every browser FPS uses. While captured:
 *   - moving the mouse turns the view and looks up and down, with separate
 *     horizontal and vertical sensitivity,
 *   - both mouse buttons shoot,
 *   - Esc releases the mouse (a browser rule that pages cannot override;
 *     handily, Esc also opens Doom's own menu).
 * The motion and button state are handed to two small functions compiled
 * into the engine (DG_EM_MouseMove / DG_EM_MouseButtons), which turn them
 * into standard Doom mouse events.
 * ========================================================================= */

// Sub-pixel remainders: sensitivity can be fractional (for example 0.5), so
// keep the fraction that did not fit into a whole pixel and add it to the
// next movement instead of throwing it away.
let mouseAccX = 0;
let mouseAccY = 0;

function pointerLocked() {
  return document.pointerLockElement === canvas;
}

// Show the capture hint only while the game runs without the mouse captured.
function updateMouseHint() {
  mousehint.style.display = (gameStarted && !pointerLocked()) ? 'block' : 'none';
}

// Capture the mouse. "Raw input" asks the browser for unaccelerated motion
// (the pointer lock unadjustedMovement option), which is what disables OS
// mouse acceleration. Not every browser supports it: newer ones return a
// promise that rejects when refused, in which case we quietly fall back to
// a plain capture so the game stays playable (just with acceleration).
// Older browsers return nothing and ignore the option, which is the same
// graceful fallback by accident.
function captureMouse() {
  const wantRaw = rawInput.checked;
  let request;
  try {
    request = canvas.requestPointerLock(wantRaw ? { unadjustedMovement: true } : undefined);
  } catch (err) {
    // A very old API that dislikes the options argument: capture plainly.
    request = canvas.requestPointerLock();
  }
  if (wantRaw && request && typeof request.catch === 'function') {
    request.catch(function () {
      console.log('Raw input (unadjustedMovement) not supported here; capturing with acceleration.');
      canvas.requestPointerLock();
    });
  }
}

// Translate held browser buttons into the engine's mouse-button bitfield.
// The engine treats bit 0 as Fire; both the left and the right mouse button
// shoot. (The first click on an uncaptured game only captures the mouse:
// buttons are not forwarded until capture is active, so that click never
// fires a shot.)
function engineButtonBits(e) {
  let bits = 0;
  if (e.buttons & 1) bits |= 1;   // left button held  -> engine Fire bit
  if (e.buttons & 2) bits |= 1;   // right button held -> engine Fire bit
  return bits;
}

document.addEventListener('mousemove', function (e) {
  if (!gameStarted || !doomModule || !pointerLocked()) return;

  // Separate sensitivities per axis: X scales turning, Y scales looking.
  const sensX = parseFloat(sensXHud.value) || 1;
  const sensY = parseFloat(sensYHud.value) || 1;
  mouseAccX += e.movementX * sensX;
  mouseAccY += e.movementY * sensY * (invertLook.checked ? -1 : 1);

  // Send whole pixels to the engine, keep the fractional remainder.
  const dx = Math.trunc(mouseAccX);
  const dy = Math.trunc(mouseAccY);
  if (dx !== 0 || dy !== 0) {
    doomModule._DG_EM_MouseMove(dx, dy);
    mouseAccX -= dx;
    mouseAccY -= dy;
  }
});

function sendMouseButtons(e) {
  if (!gameStarted || !doomModule || !pointerLocked()) return;
  e.preventDefault();
  doomModule._DG_EM_MouseButtons(engineButtonBits(e));
}
document.addEventListener('mousedown', sendMouseButtons);
document.addEventListener('mouseup', sendMouseButtons);

document.addEventListener('pointerlockchange', function () {
  updateMouseHint();
  if (!pointerLocked() && doomModule) {
    // The capture ended (Esc, alt-tab, etc.): release all engine buttons so
    // the player does not keep firing forever.
    doomModule._DG_EM_MouseButtons(0);
  }
  if (gameStarted) canvas.focus();
});

/* =========================================================================
 * FPS counter
 * -------------------------------------------------------------------------
 * The engine increments a frame counter every time it renders (see the
 * engine patch). Once a second we read that counter and show the difference
 * as frames per second. Note what this measures: how often the engine
 * RENDERS. Doom's game logic always runs at its classic fixed 35 Hz
 * regardless; the render loop is driven by the browser and can run faster.
 * ========================================================================= */

let fpsLastFrames = 0;
let fpsLastTics = 0;
let fpsLastTime = 0;

function updateFps() {
  if (!doomModule || !gameStarted) return;
  const now = performance.now();
  const frames = doomModule._DG_EM_GetFrameCount();
  const tics = doomModule._DG_EM_GetGameTic();
  if (fpsLastTime > 0 && now > fpsLastTime) {
    const dt = (now - fpsLastTime) / 1000;
    const fps = (frames - fpsLastFrames) / dt;
    const tps = (tics - fpsLastTics) / dt;
    // Two different speeds, and telling them apart matters on heavy maps:
    //   FPS  = how often the engine renders (browser driven).
    //   game = game-logic tics per second; 35 is full speed. Fewer means
    //          the map is too heavy to simulate in real time, and the game
    //          runs in slow motion (the page itself stays responsive).
    fpsbox.textContent =
      'FPS: ' + Math.round(fps) + '  |  game: ' + tps.toFixed(1) + '/35';
  }
  fpsLastFrames = frames;
  fpsLastTics = tics;
  fpsLastTime = now;
}

// The HUD checkbox shows and hides the readout (measurement itself is so
// cheap that it simply keeps running either way).
fpsToggle.addEventListener('change', function () {
  fpsbox.style.display = (fpsToggle.checked && gameStarted) ? 'block' : 'none';
  fpsToggle.blur();
  if (gameStarted) canvas.focus();
});

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
// Sensitivity needs no immediate action: the mousemove handler reads the
// current values live on every mouse movement.
wireControl(sensXSetup, sensXHud, function () {});
wireControl(sensYSetup, sensYHud, function () {});

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

// Guard so the once-a-second FPS sampler is only ever started once, no
// matter how many times the game is started and quit.
let fpsTimerStarted = false;

startBtn.addEventListener('click', function () {
  // Refuse combinations the engine itself would refuse, BEFORE tearing down
  // the setup screen, so the explanation is readable and nothing half-starts.
  if (updateSetupWarning()) {
    return;
  }

  // Lock in the key bindings the user chose (re-read on every start, so
  // changes made after a quit take effect).
  installKeyRemap(buildRemapTable());

  // Copy the setup-screen display choices into the in-game HUD controls.
  filterHud.value = filterSetup.value;
  aspectHud.value = aspectSetup.value;
  sensXHud.value  = sensXSetup.value;
  sensYHud.value  = sensYSetup.value;

  // Swap from the setup screen to the game stage.
  document.getElementById('setup').style.display = 'none';
  stage.style.display = 'flex';

  // Apply the initial filter (default: crisp / original pixels).
  setFilter(filterHud.value);

  bootEngine();
});

/* =========================================================================
 * Booting (and rebooting) the engine
 * -------------------------------------------------------------------------
 * Each call creates a COMPLETELY FRESH engine instance; the factory the
 * build exports supports that. This is what makes "quit to DOS, then Start
 * again" work: the quit hook below resets the page, and the next Start
 * boots a new engine while the WAD selections and settings stay as they
 * were.
 * ========================================================================= */

// Called from inside the engine (see the engine patch) when the player
// quits from Doom's own menu. Returns the page to the setup screen.
window.wasmBuilderOnQuit = function () {
  gameStarted = false;
  doomModule = null;
  engineLog.length = 0;
  fpsLastTime = 0;
  fpsLastFrames = 0;
  fpsLastTics = 0;

  // Release the mouse and leave fullscreen if the game held them.
  if (document.pointerLockElement === canvas) {
    document.exitPointerLock();
  }
  if (document.fullscreenElement && document.exitFullscreen) {
    document.exitFullscreen().catch(function () {});
  }

  // Hide the stage overlays and bring the setup screen back.
  errbox.style.display = 'none';
  fpsbox.style.display = 'none';
  mousehint.style.display = 'none';
  stage.style.display = 'none';
  document.getElementById('setup').style.display = 'block';
  console.log('Engine quit; returned to the setup screen.');
};

function bootEngine() {
  // Boot the WASM engine. noInitialRun keeps main() from firing until we call
  // it, so we can write the WAD into the virtual filesystem first. print and
  // printErr capture the engine's console output (see engineLogPush) while
  // still mirroring it to the browser console.
  DoomModule({
    canvas: canvas,
    noInitialRun: true,
    print: function (text) { engineLogPush(text); console.log(text); },
    printErr: function (text) { engineLogPush(text); console.warn(text); },
  }).then(function (Module) {
    // Put the chosen WAD where the engine will look for it, under the name
    // the engine should identify it by (see chooseIwadName).
    Module.FS.writeFile('/' + iwadName, wadData);

    // Write any PWADs in next to it and build the engine's command line:
    // "-file a.wad b.wad" loads them on top of the IWAD, in order.
    const wadArgs = ['-iwad', '/' + iwadName];
    const loadedPwads = pwadData.filter(function (p) { return p; });
    if (loadedPwads.length > 0) {
      wadArgs.push('-file');
      loadedPwads.forEach(function (p) {
        Module.FS.writeFile('/' + p.name, p.bytes);
        wadArgs.push('/' + p.name);
      });
    }

    // DeHackEd patch files: written under their real names (Chex Quest
    // looks for chex.deh specifically) and applied in order with -deh.
    const loadedDehs = dehData.filter(function (p) { return p; });
    if (loadedDehs.length > 0) {
      wadArgs.push('-deh');
      loadedDehs.forEach(function (p) {
        Module.FS.writeFile('/' + p.name, p.bytes);
        wadArgs.push('/' + p.name);
      });
    }

    // If any PWAD carries a DEHACKED lump, tell the engine to apply those
    // lumps too (they load last, matching classic ordering).
    if (loadedPwads.some(function (p) { return p.hasDehacked; })) {
      wadArgs.push('-dehlump');
    }

    // From here on, intercept and remap keys, and let the mouse handlers
    // reach the engine's mouse bridge.
    doomModule = Module;
    gameStarted = true;
    updateMouseHint();

    // FPS readout: visible if its HUD checkbox is ticked, sampled once a
    // second from the engine's counters. The sampler is global and started
    // only once, even across quit-and-restart cycles.
    if (fpsToggle.checked) fpsbox.style.display = 'block';
    if (!fpsTimerStarted) {
      fpsTimerStarted = true;
      setInterval(updateFps, 1000);
    }

    // Size the canvas once before we start (the MutationObserver will refine it
    // as soon as the engine sets its real buffer size during callMain).
    applyScaling();
    canvas.focus();

    // Start the engine. Emscripten's main loop "unwinds" the C stack by
    // throwing a sentinel value; that is expected, so we swallow it and log
    // anything unexpected.
    try {
      Module.callMain(wadArgs);
    } catch (err) {
      const isUnwind = (err === 'unwind') || (err && err.message === 'unwind');
      if (!isUnwind) showFatalError(err);
    }

    // Watchdog: an engine error (I_Error) exits CLEANLY, without throwing
    // anything this page could catch, which would leave a silent black
    // screen. If the engine has not rendered a single frame shortly after
    // starting, surface its own output so the reason is readable.
    setTimeout(function () {
      if (gameStarted
          && errbox.style.display !== 'block'
          && doomModule
          && doomModule._DG_EM_GetFrameCount() === 0) {
        showFatalError(new Error('The engine stopped before rendering its first frame.'));
      }
    }, 3000);

    // Now that the engine has set the real buffer size, fit to the window.
    applyScaling();
    canvas.focus();
  }).catch(showFatalError);   // any failure while booting the engine lands here
}
</script>
</body>
</html>
HTML_EOF

# Stamp the page with build info. The heredoc above is quoted ('HTML_EOF'), so
# variables are NOT expanded inside it; we substitute the placeholder here
# instead. The stamp shows on the setup screen and in the browser console,
# which makes stale-cache and forgot-to-rebuild problems obvious at a glance.
BUILD_STAMP="emsdk ${EMSDK_VERSION}, doomgeneric ${DOOMGENERIC_COMMIT:0:7} patched, ${DOOM_RESX}x${DOOM_RESY}, built $(date -u '+%Y-%m-%d %H:%M UTC')"
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

# Verify the TEXTDECODER=0 setting actually took effect. The marker to look
# for is "UTF8Decoder", the runtime's cached TextDecoder instance: it only
# exists when the string code path we opted out of was emitted. (Plain
# "TextDecoder" also appears in harmless comments, so do not grep for that.)
# The page's shim keeps even a bad build from crashing, but it is unexpected
# with the pinned toolchain, so say something.
if grep -q "UTF8Decoder" "$BUILD_DIR/doomgeneric.js"; then
  warn "doomgeneric.js still contains the TextDecoder string path. The page"
  warn "ships a shim that keeps this from crashing, but it is unexpected with"
  warn "the pinned toolchain. See the README troubleshooting section."
else
  log "Verified: doomgeneric.js uses the plain JS string decoder (as intended)."
fi

# Verify the page-facing engine exports made it into the build: the page
# calls these from JavaScript, so mouse input and the FPS counter are broken
# if the linker dropped any of them.
if grep -q "_DG_EM_MouseMove" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_MouseButtons" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_GetFrameCount" "$BUILD_DIR/doomgeneric.js" \
   && grep -q "_DG_EM_GetGameTic" "$BUILD_DIR/doomgeneric.js"; then
  log "Verified: mouse bridge and performance counter functions are exported."
else
  die "Engine exports missing from doomgeneric.js. The engine patch or EXPORTED_FUNCTIONS list did not take effect."
fi

log "Build complete."
echo ""
echo "  $BUILD_DIR/doomgeneric.js   (engine, with the .wasm embedded inside)"
echo "  $BUILD_DIR/index.html       (the page you open to play)"
echo ""
echo "Open index.html directly in a browser (double-click it, or drag it into a"
echo "tab). No web server required."
