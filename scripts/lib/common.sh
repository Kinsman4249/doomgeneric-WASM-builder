# common.sh - shared config, logging helpers, and sanity checks.
# Sourced by install.sh before any step script; every step and this file
# run in install.sh's own shell (via 'source', not a subprocess), so
# variables, functions, and the current directory all carry forward
# between files exactly as they did when this was one script.

# ---------------------------------------------------------------------------
# Configuration (override any of these by exporting the variable before
# running the script, e.g.  EMSDK_VERSION=3.1.64 ./install.sh )
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

# Detect the distro family so the package steps (and, later, the web server
# ownership rules) can branch correctly. Reads /etc/os-release, the standard
# place every modern distro describes itself. The file path can be overridden
# with OS_RELEASE_FILE, which exists purely so the detection is testable.
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
DISTRO_FAMILY=""
if [ -r "$OS_RELEASE_FILE" ]; then
  # Pull ID and ID_LIKE (e.g. ID=ubuntu, ID_LIKE="debian") in a subshell so
  # sourcing the file cannot leak variables into this script.
  DISTRO_IDS="$( . "$OS_RELEASE_FILE" 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}" )"
else
  DISTRO_IDS=""
fi

case " $DISTRO_IDS " in
  *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
  *fedora*|*rhel*)   DISTRO_FAMILY="fedora" ;;
  *)
    die "Unsupported distro (os-release says: '${DISTRO_IDS:-unreadable}'). This script supports Fedora/RHEL-family and Debian/Ubuntu-family systems. See README.md."
    ;;
esac
log "Detected distro family: $DISTRO_FAMILY"
