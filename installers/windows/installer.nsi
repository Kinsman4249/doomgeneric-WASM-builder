; DOOM (WASM) Windows installer, built with NSIS (makensis).
;
; Expects the payload already downloaded into <repo-root>/payload/index.html
; and <repo-root>/payload/doomgeneric.js, and an optional
; <repo-root>/payload/icon.ico (built by the CI job from assets/icon.png).
; NSIS resolves relative File paths against THIS SCRIPT's own directory
; (installers/windows/), not the invocation cwd, hence the ../../ below.
; Shortcuts point straight at index.html, which Windows opens with the
; default browser, so no separate launcher executable is needed.

!define APP_NAME "DOOM (WASM)"
!define INSTALL_DIR "$LOCALAPPDATA\doomgeneric-WASM"

Name "${APP_NAME}"
OutFile "doomgeneric-WASM-windows.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel user
SilentInstall normal

Section "Install"
  SetOutPath "$INSTDIR"
  File "..\..\payload\index.html"
  File "..\..\payload\doomgeneric.js"
  File /nonfatal "..\..\payload\icon.ico"

  ; $0 holds the icon path for the shortcuts below; empty means "use the
  ; target file's own icon" (CreateShortcut treats "" that way).
  StrCpy $0 ""
  IfFileExists "$INSTDIR\icon.ico" have_icon no_icon
  have_icon:
    StrCpy $0 "$INSTDIR\icon.ico"
  no_icon:

  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\index.html" "" "$0"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\index.html" "" "$0"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\index.html"
  Delete "$INSTDIR\doomgeneric.js"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
SectionEnd
