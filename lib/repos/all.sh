# =============================================================================
#  repos/all.sh — Execution order
# =============================================================================

if stage_already_run "repos"; then
  log_info "Repos stage already completed; skipping"
else
  if [[ "${NETWORK_OK:-false}" != true ]]; then
    log_info "Checking network connectivity for repos stage..."
    if check_network_connectivity dl.fedoraproject.org; then
      export NETWORK_OK=true
      log_ok "Network is reachable"
    else
      export NETWORK_OK=false
      log_error "Cannot reach Fedora mirrors. Network may be down."
      exit 1
    fi
  fi

  source "$SETUP_LIB/repos/rpm_fusion.sh"
  source "$SETUP_LIB/repos/brave.sh"
  source "$SETUP_LIB/repos/copr.sh"
fi
