[Back to README](../README.md)

# Building from source

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
   to a pinned commit, and apply the mouse-look engine patches (see
   [Engine and build patches](ENGINE-PATCHES.md) below).
5. Write a patched `Makefile.emscripten` (see
   [Engine and build patches](ENGINE-PATCHES.md) below).
6. Write `index.html` (the WAD picker, controls UI, and display controls).
7. Build and verify. The output is `~/doomgeneric/doomgeneric/doomgeneric.js`
   and `index.html`. The paths to everything, including the downloaded
   freeware games, are printed at the end.
8. Optionally deploy into an existing Apache or Nginx site on this
   machine (see [Deploying](DEPLOYING.md) below). Control
   with `WEBEXPORT=1` or `WEBEXPORT=0`, or answer the prompt.
9. Optionally package everything (page, engine, freeware pack) into a
   ready-to-upload `site/` folder plus a `doom-site.tar.gz`. All paths in
   the page are relative, so the folder works on any domain, any
   subdirectory, any static host, with zero configuration. Control with
   `SITE=1` or `SITE=0`, or answer the prompt.
10. If a web deploy happened, optionally clean up the local copies (see
    [Deploying](DEPLOYING.md) below). Control with `CLEANUP=1` or
    `CLEANUP=0`, or answer the prompt.

When it finishes, open `~/doomgeneric/doomgeneric/index.html` directly in a
browser. If the container shares your home directory with the host (the
Distrobox default), that same path exists on your host too, so you can open it
from your host file manager or browser.

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
