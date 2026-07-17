# =============================================================================
#  distrobox.sh — Optional Distrobox with rootless Podman
# =============================================================================

DISTROBOX_MARKER="$SETUP_PACKAGES/distrobox.enable"

if [[ ! -e "$DISTROBOX_MARKER" ]]; then
  log_info "distrobox.enable not found; skipping Distrobox"
elif [[ ! -f "$DISTROBOX_MARKER" ]]; then
  log_error "Distrobox opt-in is not a regular file: $DISTROBOX_MARKER"
  exit 1
else
  if ! resolve_target_user "${TARGET_USER:-}"; then
    log_error "Could not resolve the target user for Distrobox installation"
    exit 1
  fi

  log_info "Installing Distrobox with the rootless Podman backend..."
  pkg_install "podman" "distrobox"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would verify rootless Podman as $TARGET_USER"
  else
    rootless_status="$(target_user_command podman info --format '{{.Host.Security.Rootless}}' 2>>"$SETUP_LOG" || true)"
    if [[ "$rootless_status" != "true" ]]; then
      log_error "Podman did not report a working rootless configuration for $TARGET_USER"
      log_error "Podman output: ${rootless_status:-no output; see $SETUP_LOG}"
      exit 1
    fi

    podman_version="$(target_user_command podman --version)"
    distrobox_version="$(target_user_command distrobox --version)"
    log_ok "Rootless Podman verified: $podman_version"
    log_ok "Distrobox installed: $distrobox_version"
  fi

  log_info "No containers are created automatically; use distrobox-create after login"
fi
