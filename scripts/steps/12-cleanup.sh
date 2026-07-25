# 12-cleanup.sh - optional cleanup after a web deploy.
#
# Offered ONLY when the web deploy step actually completed. Verifies the
# deployed copy is present and non-empty before deleting anything, deletes
# only build artifacts (never the cloned source, unless separately
# confirmed), and lists exactly what was removed.
# Control with CLEANUP=1 / CLEANUP=0; unset asks when a terminal is
# available.

if [ "$WEBEXPORT_DONE" = "1" ]; then
  if [ -z "${CLEANUP:-}" ]; then
    if [ -t 0 ]; then
      echo ""
      echo "The build has been deployed to $WEBEXPORT_DIR/."
      read -r -p "Remove the extra local copies now that the site copy exists? This deletes the build output and any downloaded freeware pack outside the web server directory. [y/N]: " CL_ANS
      case "${CL_ANS:-N}" in
        [Yy]*) CLEANUP=1 ;;
        *)     CLEANUP=0 ;;
      esac
    else
      CLEANUP=0
    fi
  fi

  if [ "$CLEANUP" = "1" ]; then
    # Never delete on trust: confirm the deployed copy is real first.
    if [ ! -s "$WEBEXPORT_DIR/index.html" ] || [ ! -s "$WEBEXPORT_DIR/doomgeneric.js" ]; then
      warn "Deployed copy at $WEBEXPORT_DIR is missing or empty; NOT deleting anything."
    else
      DELETED=()

      # Build artifacts (the source tree stays; a re-run rebuilds these).
      for item in "$BUILD_DIR/doomgeneric.js" "$BUILD_DIR/index.html"; do
        if [ -f "$item" ]; then rm -f "$item"; DELETED+=("$item"); fi
      done
      if [ -d "$BUILD_DIR/build" ]; then
        rm -rf "$BUILD_DIR/build"; DELETED+=("$BUILD_DIR/build/")
      fi
      if [ -d "$BUILD_DIR/freeware" ]; then
        rm -rf "$BUILD_DIR/freeware"; DELETED+=("$BUILD_DIR/freeware/")
      fi

      # The site/ folder and tarball from the packaging step are only
      # deleted with a specific confirmation, since the user asked for
      # them separately in this same run.
      if [ "$SITE_MADE" = "1" ] && { [ -d "$BUILD_DIR/site" ] || [ -f "$BUILD_DIR/doom-site.tar.gz" ]; }; then
        SITE_CL="n"
        if [ -t 0 ]; then
          read -r -p "Also delete the packaged site folder and doom-site.tar.gz made earlier in this run? [y/N]: " SITE_CL
        fi
        case "${SITE_CL:-n}" in
          [Yy]*)
            [ -d "$BUILD_DIR/site" ] && rm -rf "$BUILD_DIR/site" && DELETED+=("$BUILD_DIR/site/")
            [ -f "$BUILD_DIR/doom-site.tar.gz" ] && rm -f "$BUILD_DIR/doom-site.tar.gz" && DELETED+=("$BUILD_DIR/doom-site.tar.gz")
            ;;
          *) log "Keeping the packaged site folder and tarball." ;;
        esac
      fi

      # Source removal is opt-in and separate: without the clone you cannot
      # rebuild without re-cloning.
      SRC_CL="n"
      if [ -t 0 ]; then
        read -r -p "ALSO delete the cloned source repo at $DOOMGENERIC_DIR (prevents rebuilding without re-cloning)? [y/N]: " SRC_CL
      fi
      case "${SRC_CL:-n}" in
        [Yy]*)
          rm -rf "$DOOMGENERIC_DIR"
          DELETED+=("$DOOMGENERIC_DIR/")
          ;;
        *) log "Keeping the cloned source repo (re-run ./install.sh to rebuild any time)." ;;
      esac

      echo ""
      echo "Deleted:"
      for item in ${DELETED[@]+"${DELETED[@]}"}; do
        echo "  $item"
      done
      echo ""
      echo "Kept: $WEBEXPORT_DIR/ (the deployed site copy)"
    fi
  else
    log "Cleanup declined; all local files left in place."
  fi
fi
