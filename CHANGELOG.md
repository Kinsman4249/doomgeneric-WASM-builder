# Changelog

## v2.2.0 (2026-07-24)

The release workflow now builds and publishes three platform-specific installers alongside the source archive. Each tagged release now includes a self-extracting Linux installer (built with makeself), a Windows GUI installer (built with NSIS), and a macOS disk image containing an app bundle (built with hdiutil), all three built from the exact same engine and index.html. Users no longer need to install the Emscripten toolchain, Fedora, Debian, or Distrobox—they can download a ready-to-run installer for their platform from the Releases page.

The README now documents these prebuilt installers, including installation instructions and behavior notes (Linux adds a .desktop entry and app-menu shortcut, Windows adds Start Menu and Desktop shortcuts, macOS uses a standard drag-to-Applications .dmg). The build process includes optional icon support (assets/icon.png is automatically converted to .ico for Windows and .icns for macOS, with graceful fallback if the icon is missing).

The CI workflow was restructured into five jobs: a single upstream build-payload job that produces the web artifacts, three independent packaging jobs that download the payload and wrap it for their respective platforms, and a final release job that collects all three installers plus source archives and publishes one GitHub Release.
