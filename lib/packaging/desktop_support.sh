# =============================================================================
#  desktop_support.sh — Required packages for core desktop functions
# =============================================================================

log_info "Installing desktop support packages..."
pkg_install_from_list "$SETUP_PACKAGES/desktop-support.packages"
