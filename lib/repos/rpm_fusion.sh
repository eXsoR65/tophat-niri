# =============================================================================
#  rpm_fusion.sh — Enable RPM Fusion free + nonfree (as you requested)
#  Needed for: media codecs, NVIDIA drivers (if applicable)
# =============================================================================

if [[ "${NETWORK_OK:-false}" != true ]]; then
  log_warn "Skipping RPM Fusion — no network"
  return 0
fi

log_info "Setting up RPM Fusion repositories"
repo_enable_rpm_fusion

# Refresh metadata
run_logged "Refreshing package metadata" dnf makecache
