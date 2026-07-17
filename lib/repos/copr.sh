# =============================================================================
#  copr.sh — Enable COPR repositories for niri and DMS (stable only)
#
#  Values from install.sh exports:
#    NIRI_COPR="yalter/niri"
#    DMS_COPR="avengemedia/dms"
#
#  Note: Enabling avengemedia/dms auto-enables avengemedia/danklinux
#  as a dependency, which provides quickshell, material-symbols-fonts,
#  and matugen at runtime.
# =============================================================================

if [[ "${NETWORK_OK:-false}" != true ]]; then
  log_warn "Skipping COPR repos — no network"
  return 0
fi

# niri (stable)
log_info "Enabling niri COPR: $NIRI_COPR"
enable_copr "$NIRI_COPR"

# DankMaterialShell (stable) — auto-enables danklinux dependency repo
log_info "Enabling DMS COPR: $DMS_COPR"
enable_copr "$DMS_COPR"

# Ghostty Terminal stable
log_info "Enabling GHOSTTY COPR: $GHOSTTY_COPR"
enable_copr "$GHOSTTY_COPR"

# Refresh metadata after adding repos
run_logged "Refreshing package metadata" dnf makecache
