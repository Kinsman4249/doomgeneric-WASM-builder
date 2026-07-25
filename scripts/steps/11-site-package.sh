# 11-site-package.sh - optional: package everything for a web server.
#
# Collects the page, the engine, and the freeware pack (if present) into one
# folder plus a tarball, ready to upload to any static web host. Everything
# the page references is a RELATIVE path, so it works under any domain,
# subdomain, or subdirectory with zero configuration.
# Control with SITE=1 (package) or SITE=0 (skip); unset asks when a
# terminal is available.
if [ -z "${SITE:-}" ]; then
  if [ -t 0 ]; then
    read -r -p "Package everything into a ready-to-upload website folder? [y/N]: " SITE_ANS
    case "${SITE_ANS:-N}" in
      [Yy]*) SITE=1 ;;
      *)     SITE=0 ;;
    esac
  else
    SITE=0
  fi
fi

SITE_MADE=0
if [ "$SITE" = "1" ]; then
  SITE_MADE=1
  log "Packaging the website folder..."
  SITE_DIR="$BUILD_DIR/site"
  rm -rf "$SITE_DIR"
  mkdir -p "$SITE_DIR"
  cp "$BUILD_DIR/index.html" "$BUILD_DIR/doomgeneric.js" "$SITE_DIR/"
  if [ -d "$BUILD_DIR/freeware" ]; then
    cp -r "$BUILD_DIR/freeware" "$SITE_DIR/freeware"
  fi
  tar -czf "$BUILD_DIR/doom-site.tar.gz" -C "$SITE_DIR" .
  echo ""
  echo "  Website folder:  $SITE_DIR/"
  echo "  Tarball:         $BUILD_DIR/doom-site.tar.gz"
  echo ""
  echo "Upload the folder's CONTENTS (or extract the tarball) anywhere a web"
  echo "server can serve static files. All paths are relative, so it works on"
  echo "any domain name, any subfolder, no configuration. To try it locally:"
  echo ""
  echo "  cd \"$SITE_DIR\" && python3 -m http.server 8000"
  echo "  then open http://localhost:8000/"
fi
