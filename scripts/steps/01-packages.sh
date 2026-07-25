# 01-packages.sh - install the system packages the build needs.
# The tools the build needs. On Fedora, gcc and gcc-c++ are separate
# packages; on Debian, build-essential supplies both compilers.
if [ "$DISTRO_FAMILY" = "debian" ]; then
  REQUIRED_PKGS=(git make cmake python3 build-essential patch)
  PKG_CHECK() { dpkg -s "$1" >/dev/null 2>&1; }
  PKG_INSTALL_HINT="apt-get install -y"
else
  REQUIRED_PKGS=(git make cmake python3 gcc gcc-c++ patch)
  PKG_CHECK() { rpm -q "$1" >/dev/null 2>&1; }
  PKG_INSTALL_HINT="dnf install -y"
fi

log "Checking required packages (${REQUIRED_PKGS[*]})..."
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  PKG_CHECK "$pkg" || MISSING_PKGS+=("$pkg")
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
    warn "  $PKG_INSTALL_HINT ${MISSING_PKGS[*]}"
  fi
  if [ "$DISTRO_FAMILY" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y "${MISSING_PKGS[@]}"
  else
    sudo dnf install -y "${MISSING_PKGS[@]}"
  fi
else
  log "All required packages already present."
fi
