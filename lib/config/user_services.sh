# =============================================================================
#  user_services.sh
#  Configures DMS and niri at the user level.
#  Writes config files directly instead of invoking systemctl --user,
#  which can hang when no user D-Bus session is active.
# =============================================================================

# Resolve target user here too so --select config is safe even when
# preflight was not selected in the same run.
if ! resolve_target_user "${TARGET_USER:-}"; then
  log_error "Could not resolve a non-root target user with a valid home directory"
  log_error "Run via sudo from the target account, or set SUDO_USER/TARGET_USER explicitly"
  exit 1
fi

log_info "Configuring user-level services for $TARGET_USER..."

# -----------------------------------------------------------------------------
# Create user config directories
# -----------------------------------------------------------------------------
log_info "Creating user config directories..."
if [[ "$DRY_RUN" != true ]]; then
  mkdir -p "${TARGET_USER_HOME}/.config/systemd/user"
  mkdir -p "${TARGET_USER_HOME}/.config/environment.d"
  mkdir -p "${TARGET_USER_HOME}/.config/niri"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_USER_HOME}/.config"
  log_ok "Config directories created"
fi

# -----------------------------------------------------------------------------
# XDG user directories
# -----------------------------------------------------------------------------
run_as_target_user "Creating standard user directories for $TARGET_USER" \
  xdg-user-dirs-update

# -----------------------------------------------------------------------------
# DMS Setup — generates starter niri configs
# 'dms setup' requires a graphical session and never succeeds from this root
# installer context, so Tophat intentionally does not run it. The finalize
# summary reminds the user to run it after the first graphical login.
# -----------------------------------------------------------------------------
log_info "Skipping 'dms setup' (requires graphical session) — run it after first login"

# -----------------------------------------------------------------------------
# DMS systemd user service — create symlink directly
# Instead of: systemctl --user enable dms.service
# We create: ~/.config/systemd/user/niri.service.wants/dms.service
# -----------------------------------------------------------------------------
log_info "Linking DMS to niri session..."
if [[ "$DRY_RUN" != true ]]; then
  # Create the wants directory for niri.service
  WANTS_DIR="${TARGET_USER_HOME}/.config/systemd/user/niri.service.wants"
  mkdir -p "$WANTS_DIR"

  # Find where dms.service is installed
  DMS_SERVICE_PATH=""
  for dir in /usr/lib/systemd/user /usr/local/lib/systemd/user; do
    if [[ -f "$dir/dms.service" ]]; then
      DMS_SERVICE_PATH="$dir/dms.service"
      break
    fi
  done

  if [[ -n "$DMS_SERVICE_PATH" ]]; then
    ln -sf "$DMS_SERVICE_PATH" "$WANTS_DIR/dms.service"
    chown -R "${TARGET_USER}:${TARGET_USER}" "$WANTS_DIR"
    log_ok "DMS linked to niri.service (symlink created)"
  else
    log_warn "Could not find dms.service in system user units"
    log_warn "Will need manual: systemctl --user add-wants niri.service dms.service"
  fi
fi

# -----------------------------------------------------------------------------
# Important note
# -----------------------------------------------------------------------------
log_ok "User configuration complete"
log_info ""
log_info "Do NOT add 'dms run' to niri config — the systemd service handles startup."
log_info ""
