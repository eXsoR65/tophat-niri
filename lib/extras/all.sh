# =============================================================================
#  extras/all.sh — Optional user software ecosystems
# =============================================================================

if stage_already_run "extras"; then
  log_info "Extras stage already completed; skipping"
elif [[ ! -e "$SETUP_PACKAGES/flatpaks.packages" &&
        ! -e "$SETUP_PACKAGES/distrobox.enable" &&
        ! -e "$SETUP_PACKAGES/homebrew.packages" ]]; then
  skip_stage "extras" "No optional extras are enabled; skipping extras stage"
else
  source "$SETUP_LIB/extras/flatpak.sh"
  source "$SETUP_LIB/extras/distrobox.sh"
  source "$SETUP_LIB/extras/homebrew.sh"
fi
