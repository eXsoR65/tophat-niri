# =============================================================================
#  applications.sh — Install user applications
#
#  Copy Template ./packages/applications.packages.template to
#  ./packages/applications.packages and add your desired apps
# =============================================================================

log_info "Installing user applications..."
if [[ -f "$SETUP_PACKAGES/applications.packages" ]]; then
  pkg_install_from_list "$SETUP_PACKAGES/applications.packages"
else
  log_info "No applications.packages; skipping user app installs (copy the template to opt in)"
fi
