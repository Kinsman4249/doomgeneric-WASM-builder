# 10-webexport.sh - optional deploy into an existing Apache or Nginx site.
#
# Looks for web servers already configured on THIS machine, lists their
# sites' document roots, and copies the build into a doomgeneric-WASM/
# subfolder of the one you pick. It never touches the web server's own
# configuration and never reloads anything: whatever domain or vhost
# already points at that site root simply gains a /doomgeneric-WASM/ path.
# Control with WEBEXPORT=1 / WEBEXPORT=0; unset asks when a terminal is
# available. Skipped silently when declined or when no server is found.

WEBEXPORT_DONE=0
WEBEXPORT_DIR=""

if [ -z "${WEBEXPORT:-}" ]; then
  if [ -t 0 ]; then
    read -r -p "Check this system for existing Apache or Nginx sites to deploy the Doom build into? [y/N]: " WE_ANS
    case "${WE_ANS:-N}" in
      [Yy]*) WEBEXPORT=1 ;;
      *)     WEBEXPORT=0 ;;
    esac
  else
    WEBEXPORT=0
  fi
fi

# Pull ServerName/DocumentRoot pairs out of an Apache config file.
# Prints "name<TAB>root" (name may be empty).
parse_apache_conf() {
  awk '
    /^[[:space:]]*ServerName[[:space:]]/   { name=$2 }
    /^[[:space:]]*DocumentRoot[[:space:]]/ {
      root=$2; gsub(/"/, "", root);
      print name "\t" root; name=""
    }
  ' "$1" 2>/dev/null
}

# Pull server_name/root pairs out of an nginx config file.
parse_nginx_conf() {
  awk '
    /^[[:space:]]*server_name[[:space:]]/ { name=$2; gsub(/;/, "", name) }
    /^[[:space:]]*root[[:space:]]/ {
      root=$2; gsub(/[";]/, "", root);
      print name "\t" root; name=""
    }
  ' "$1" 2>/dev/null
}

if [ "$WEBEXPORT" = "1" ]; then
  log "Looking for installed web servers..."

  HAVE_APACHE=0
  HAVE_NGINX=0
  if [ "$DISTRO_FAMILY" = "debian" ]; then
    command -v apache2 >/dev/null 2>&1 && [ -d /etc/apache2 ] && HAVE_APACHE=1
  else
    command -v httpd >/dev/null 2>&1 && [ -d /etc/httpd ] && HAVE_APACHE=1
  fi
  command -v nginx >/dev/null 2>&1 && [ -d /etc/nginx ] && HAVE_NGINX=1

  if [ "$HAVE_APACHE" = "0" ] && [ "$HAVE_NGINX" = "0" ]; then
    log "No Apache or Nginx installation found; skipping web deploy."
  else
    # Enumerate sites: three parallel arrays (server kind, display name,
    # document root), deduplicated on the root path.
    SITE_KINDS=()
    SITE_NAMES=()
    SITE_ROOTS=()

    add_site() {   # kind, name, root
      local k="$1" n="$2" r="$3" existing
      [ -n "$r" ] || return 0
      for existing in ${SITE_ROOTS[@]+"${SITE_ROOTS[@]}"}; do
        [ "$existing" = "$r" ] && return 0
      done
      SITE_KINDS+=("$k")
      SITE_NAMES+=("${n:-(no server name)}")
      SITE_ROOTS+=("$r")
    }

    collect_from() {   # kind, parser, glob...
      local kind="$1" parser="$2" f parsed name root
      shift 2
      for f in "$@"; do
        [ -f "$f" ] || continue
        # A here-string instead of process substitution: it behaves the
        # same but does not depend on /dev/fd existing.
        parsed="$("$parser" "$f")" || parsed=""
        while IFS=$'\t' read -r name root; do
          add_site "$kind" "$name" "$root"
        done <<< "$parsed"
      done
    }

    if [ "$HAVE_APACHE" = "1" ]; then
      if [ "$DISTRO_FAMILY" = "debian" ]; then
        collect_from apache parse_apache_conf /etc/apache2/sites-enabled/*.conf /etc/apache2/sites-enabled/*
      else
        collect_from apache parse_apache_conf /etc/httpd/conf.d/*.conf
      fi
    fi
    if [ "$HAVE_NGINX" = "1" ]; then
      if [ "$DISTRO_FAMILY" = "debian" ]; then
        collect_from nginx parse_nginx_conf /etc/nginx/sites-enabled/*
      else
        collect_from nginx parse_nginx_conf /etc/nginx/conf.d/*.conf
      fi
    fi

    echo ""
    echo "Discovered sites:"
    i=1
    for idx in ${SITE_ROOTS[@]+"${!SITE_ROOTS[@]}"}; do
      printf '  %d) [%s] %s  ->  %s\n' "$i" "${SITE_KINDS[$idx]}" "${SITE_NAMES[$idx]}" "${SITE_ROOTS[$idx]}"
      i=$((i + 1))
    done
    MANUAL_OPT=$i
    SKIP_OPT=$((i + 1))
    echo "  ${MANUAL_OPT}) Enter a path manually"
    echo "  ${SKIP_OPT}) Skip, do not deploy to a web server"
    echo ""
    read -r -p "Selection [1-${SKIP_OPT}]: " WE_CHOICE

    TARGET_ROOT=""
    TARGET_KIND=""
    if ! [[ "${WE_CHOICE:-}" =~ ^[0-9]+$ ]] || [ "$WE_CHOICE" -lt 1 ] || [ "$WE_CHOICE" -gt "$SKIP_OPT" ]; then
      warn "Selection '$WE_CHOICE' is not in range; skipping web deploy."
    elif [ "$WE_CHOICE" = "$SKIP_OPT" ]; then
      log "Web deploy skipped."
    elif [ "$WE_CHOICE" = "$MANUAL_OPT" ]; then
      read -r -p "Site root path: " TARGET_ROOT
      # A manual path has no config file to name the server; assume the one
      # that is installed (Apache first when both are).
      if [ "$HAVE_APACHE" = "1" ]; then TARGET_KIND="apache"; else TARGET_KIND="nginx"; fi
    else
      TARGET_ROOT="${SITE_ROOTS[$((WE_CHOICE - 1))]}"
      TARGET_KIND="${SITE_KINDS[$((WE_CHOICE - 1))]}"
    fi

    if [ -n "$TARGET_ROOT" ]; then
      if [ ! -d "$TARGET_ROOT" ]; then
        warn "'$TARGET_ROOT' is not a directory; skipping web deploy."
      else
        WEBEXPORT_DIR="$TARGET_ROOT/doomgeneric-WASM"
        log "Deploying into $WEBEXPORT_DIR ..."

        # Idempotent: clear and recreate ONLY our own subfolder. Nothing
        # else in the site root is touched.
        sudo rm -rf "$WEBEXPORT_DIR"
        sudo mkdir -p "$WEBEXPORT_DIR"
        sudo cp "$BUILD_DIR/index.html" "$BUILD_DIR/doomgeneric.js" "$WEBEXPORT_DIR/"
        if [ -d "$BUILD_DIR/freeware" ]; then
          sudo cp -r "$BUILD_DIR/freeware" "$WEBEXPORT_DIR/freeware"
        fi

        # Least-privilege static-site permissions, owned by the account the
        # detected web server actually runs as on this distro family.
        if [ "$DISTRO_FAMILY" = "debian" ]; then
          WEB_USER="www-data"
        elif [ "$TARGET_KIND" = "nginx" ]; then
          WEB_USER="nginx"
        else
          WEB_USER="apache"
        fi
        sudo chown -R "$WEB_USER:$WEB_USER" "$WEBEXPORT_DIR"
        sudo find "$WEBEXPORT_DIR" -type d -exec chmod 755 {} +
        sudo find "$WEBEXPORT_DIR" -type f -exec chmod 644 {} +

        # Fedora: give the files the right SELinux context so httpd/nginx
        # may actually read them.
        if [ "$DISTRO_FAMILY" = "fedora" ] && command -v getenforce >/dev/null 2>&1; then
          SEMODE="$(getenforce 2>/dev/null || echo Disabled)"
          if [ "$SEMODE" != "Disabled" ] && command -v restorecon >/dev/null 2>&1; then
            sudo restorecon -R "$WEBEXPORT_DIR"
          fi
        fi

        WEBEXPORT_DONE=1
        echo ""
        echo "  Deployed to:  $WEBEXPORT_DIR/"
        echo "  Browse to:    <your site's address>/doomgeneric-WASM/"
        echo ""
      fi
    fi
  fi
fi
