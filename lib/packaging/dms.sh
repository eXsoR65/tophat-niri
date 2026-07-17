# =============================================================================
#  dms.sh — Install DankMaterialShell (stable, from avengemedia/dms COPR)
# =============================================================================

# Install DMS itself
log_info "Installing DankMaterialShell (stable)..."
if pkg_missing "dms"; then
  run_logged "Installing DMS package" dnf install -y dms
else
  log_ok "DMS already installed"
fi

# Install DMS greeter package directly. This avoids the interactive
# `dms greeter install` flow while still using the official COPR package.
log_info "Installing DMS greeter package..."
pkg_install "dms-greeter"

# Install companion packages
log_info "Installing DMS companion packages..."
pkg_install_from_list "$SETUP_PACKAGES/dms-companions.packages"
