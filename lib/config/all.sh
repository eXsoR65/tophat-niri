# =============================================================================
#  config/all.sh — Execution order for config stage
# =============================================================================

run_config_stage() {
  if stage_already_run "config"; then
    log_info "Config stage already completed; skipping"
    return 0
  fi

  source "$SETUP_LIB/config/user_services.sh"
  source "$SETUP_LIB/config/dotfiles.sh"
  # Add more config modules here as needed
}
