; DOOM (WASM) Windows installer, built with NSIS (makensis).
;
; Expects the payload already downloaded into <repo-root>/payload/index.html
; and <repo-root>/payload/doomgeneric.js, and an optional
; <repo-root>/payload/icon.ico (built by the CI job from assets/icon.png).
; NSIS resolves relative File paths against THIS SCRIPT's own directory
; (installers/windows/), not the invocation cwd, hence the ../../ below.
; Shortcuts point straight at index.html, which Windows opens with the
; default browser, so no separate launcher executable is needed.
;
; Shows a wizard (Components page lets the user pick optional freeware
; WADs) rather than installing silently, since there is now something to
; choose. Each checked title's WAD(s) are fetched at install time by
; freeware-pack.ps1 (this script's own port of assets/freeware_pack.py -
; Windows has no python3 by default).

!include "MUI2.nsh"

!define APP_NAME "DOOM (WASM)"
!define INSTALL_DIR "$LOCALAPPDATA\doomgeneric-WASM"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\doomgeneric-WASM"

; Passed in by CI as /DVERSION=x.y.z; falls back to a placeholder for local
; `makensis installer.nsi` runs that don't set it.
!ifndef VERSION
  !define VERSION "0.0.0-dev"
!endif

Name "${APP_NAME}"
OutFile "doomgeneric-WASM-windows.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel user

Var FreewareKeys

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------
; Required: the game itself.
; ---------------------------------------------------------------------------
Section "DOOM (WASM)" SEC_CORE
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "..\..\payload\index.html"
  File "..\..\payload\doomgeneric.js"
  File /nonfatal "..\..\payload\icon.ico"
  File "freeware-pack.ps1"

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

  ; Control Panel > Programs and Features entry. HKCU (not HKLM) matches
  ; RequestExecutionLevel user and the per-user %LOCALAPPDATA% install dir.
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$0"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Kinsman4249"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

; ---------------------------------------------------------------------------
; Optional freeware WADs. Each section just appends its freeware_pack.py
; key group to $FreewareKeys (space-separated); the trailing hidden section
; below does the actual download once, after all choices are known. Group
; matches assets/index.html's FREEWARE_TITLES and assets/freeware_pack.py's
; PLAN - keep the three in sync.
; ---------------------------------------------------------------------------
SectionGroup "Free games (downloaded during install, none bundled)" SEC_GROUP_FREEWARE
  Section /o "Doom Shareware (~4 MB)" SEC_DOOM1
    StrCpy $FreewareKeys "$FreewareKeys doom1"
  SectionEnd
  Section /o "Freedoom Phase 1 (~16 MB)" SEC_FD1
    StrCpy $FreewareKeys "$FreewareKeys freedoom1"
  SectionEnd
  Section /o "Freedoom Phase 2 (~28 MB)" SEC_FD2
    StrCpy $FreewareKeys "$FreewareKeys freedoom2"
  SectionEnd
  Section /o "HACX 1.2" SEC_HACX
    StrCpy $FreewareKeys "$FreewareKeys hacx"
  SectionEnd
  Section /o "Chex Quest Trilogy" SEC_CHEX
    StrCpy $FreewareKeys "$FreewareKeys chex3v chex3v_deh chex3v_readme"
  SectionEnd
  Section /o "Harmony" SEC_HARMONY
    StrCpy $FreewareKeys "$FreewareKeys freedoom2 harmonyc harmony_deh"
  SectionEnd
  Section /o "WolfenDoom: First Encounter" SEC_WOLFEN
    StrCpy $FreewareKeys "$FreewareKeys freedoom2 wolfen1 wolfen1_readme"
  SectionEnd
  Section /o "STRAIN" SEC_STRAIN
    StrCpy $FreewareKeys "$FreewareKeys freedoom2 strain strain_deh strain_readme strain_package"
  SectionEnd
SectionGroupEnd

; Hidden (leading '-'), always runs last: the actual download, once, for
; whatever titles ended up selected above.
Section "-FreewareDownload"
  StrCmp $FreewareKeys "" freeware_done
    DetailPrint "Downloading selected free games..."
    nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\freeware-pack.ps1" -OutDir "$INSTDIR\freeware" -Keys $FreewareKeys'
    Pop $0
  freeware_done:
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CORE} "The game itself (required)."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_GROUP_FREEWARE} "Freely redistributable WADs, fetched from their original sources during install. Skip all of these and use the in-page WAD picker later if you'd rather supply your own."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  Delete "$INSTDIR\index.html"
  Delete "$INSTDIR\doomgeneric.js"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\freeware-pack.ps1"
  Delete "$INSTDIR\uninstall.exe"
  RMDir /r "$INSTDIR\freeware"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
