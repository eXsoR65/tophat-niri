# =============================================================================
#  system_update.sh — System upgrade and base utility installation
# =============================================================================

log "Updating system packages..."
run_logged "System update" dnf upgrade -y --refresh

log "Installing base utilities..."
pkg_install_from_list "$SETUP_PACKAGES/base-utils.packages"
