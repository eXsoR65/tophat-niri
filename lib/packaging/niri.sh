# =============================================================================
#  niri.sh — Install niri compositor (stable, from yalter/niri COPR)
# =============================================================================

# Niri COPR was already enabled in repos/copr.sh, so just install
log_info "Installing niri compositor..."
pkg_install "niri"

# Verify session registration for display manager/greeter
if file_exists "/usr/share/wayland-sessions/niri.desktop"; then
  log_ok "niri session registered for display manager"
else
  log_warn "niri session file not found at expected location"
  log_warn "Check: ls /usr/share/wayland-sessions/"
fi
