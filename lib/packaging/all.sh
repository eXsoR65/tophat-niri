# =============================================================================
#  packaging/all.sh — Execution order
# =============================================================================

run_packaging_stage() {
  if stage_already_run "packaging"; then
    log_info "Packaging stage already completed; skipping"
    return 0
  fi

  source "$SETUP_LIB/packaging/desktop_support.sh"
  source "$SETUP_LIB/packaging/hardware_firmware.sh"
  source "$SETUP_LIB/packaging/niri.sh"
  source "$SETUP_LIB/packaging/dms.sh"
  source "$SETUP_LIB/packaging/remove_replaced.sh"
  source "$SETUP_LIB/packaging/applications.sh"
}
