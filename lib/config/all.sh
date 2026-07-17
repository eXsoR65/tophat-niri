# =============================================================================
#  config/all.sh — Execution order for config stage
# =============================================================================

if stage_already_run "config"; then
  log_info "Config stage already completed; skipping"
else
  source "$SETUP_LIB/config/user_services.sh"
  source "$SETUP_LIB/config/dotfiles.sh"
  # Add more config modules here as needed
fi
