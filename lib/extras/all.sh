# =============================================================================
#  extras/all.sh — Optional user software ecosystems
# =============================================================================

run_extras_stage() {
  if stage_already_run "extras"; then
    log_info "Extras stage already completed; skipping"
    return 0
  fi

  if [[ ! -e "$SETUP_PACKAGES/flatpaks.packages" &&
    ! -e "$SETUP_PACKAGES/distrobox.enable" &&
    ! -e "$SETUP_PACKAGES/homebrew.packages" ]]; then
    skip_stage "extras" "No optional extras are enabled; skipping extras stage"
    return 0
  fi

  source "$SETUP_LIB/extras/flatpak.sh"
  source "$SETUP_LIB/extras/distrobox.sh"
  source "$SETUP_LIB/extras/homebrew.sh"
}
