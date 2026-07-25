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
# This script is a thin orchestrator: the actual work lives in
# scripts/lib/common.sh (shared config and helpers) and the numbered
# scripts/steps/*.sh files, run in order below. Large generated files
# (the engine patch, the Makefile template, index.html, the freeware
# downloader) live under assets/ as real, syntax-highlightable files
# instead of being embedded as heredocs in this script.
#
# ---------------------------------------------------------------------------
# A quick primer for readers new to bash:
#   - Lines starting with '#' are comments (ignored by the shell).
#   - VAR="value" sets a variable. "$VAR" reads it back.
#   - "${VAR:-default}" means "use $VAR if it is set, otherwise use default".
#   - Functions are declared as: name() { ...commands... }
#   - '&&' runs the next command only if the previous one succeeded.
#   - 'source file.sh' runs file.sh in THIS shell, so any variables,
#     functions, or 'cd's it does are still in effect afterward. That is
#     how the step scripts below share state (like $BUILD_DIR) with each
#     other and with this file.
# ---------------------------------------------------------------------------

# 'set -e'  : stop the whole script the moment any command fails.
# 'set -u'  : treat the use of an undefined variable as an error.
# 'set -o pipefail' : if any command in a pipe (a | b) fails, the pipe fails.
# Together these make the script fail loudly and early instead of limping on.
set -euo pipefail

# Directory this script lives in, so steps can find scripts/ and assets/
# regardless of the caller's current directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/scripts/lib/common.sh"

# shellcheck source=scripts/steps/01-packages.sh
source "$SCRIPT_DIR/scripts/steps/01-packages.sh"      # 1. System packages
# shellcheck source=scripts/steps/02-emsdk.sh
source "$SCRIPT_DIR/scripts/steps/02-emsdk.sh"          # 2. Emscripten SDK
# shellcheck source=scripts/steps/03-source.sh
source "$SCRIPT_DIR/scripts/steps/03-source.sh"         # 3. doomgeneric source
# shellcheck source=scripts/steps/04-engine-patch.sh
source "$SCRIPT_DIR/scripts/steps/04-engine-patch.sh"   # 3.5 Engine patches
# shellcheck source=scripts/steps/05-dehacked.sh
source "$SCRIPT_DIR/scripts/steps/05-dehacked.sh"       # 3.6 DeHackEd sources
# shellcheck source=scripts/steps/06-makefile.sh
source "$SCRIPT_DIR/scripts/steps/06-makefile.sh"       # 4. Patched Makefile.emscripten
# shellcheck source=scripts/steps/07-index-html.sh
source "$SCRIPT_DIR/scripts/steps/07-index-html.sh"     # 5. index.html
# shellcheck source=scripts/steps/08-freeware.sh
source "$SCRIPT_DIR/scripts/steps/08-freeware.sh"       # 5.5 Optional freeware game pack
# shellcheck source=scripts/steps/09-build.sh
source "$SCRIPT_DIR/scripts/steps/09-build.sh"          # 6. Build
# shellcheck source=scripts/steps/10-webexport.sh
source "$SCRIPT_DIR/scripts/steps/10-webexport.sh"      # 6.5 Optional web server deploy
# shellcheck source=scripts/steps/11-site-package.sh
source "$SCRIPT_DIR/scripts/steps/11-site-package.sh"   # 7. Optional website packaging
# shellcheck source=scripts/steps/12-cleanup.sh
source "$SCRIPT_DIR/scripts/steps/12-cleanup.sh"        # 8. Optional post-deploy cleanup
