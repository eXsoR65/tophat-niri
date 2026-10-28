# =============================================================================
#  services/all.sh — Configure system services for niri + DMS desktop
#
#  Note: PipeWire services are user-session units on Fedora. They start
#  automatically when the user logs in.
# =============================================================================

GREETD_CONFIG_DEFAULT="/etc/greetd/config.toml"

_greetd_config_body() {
  cat <<'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
GREETD_EOF
}

# Write the greeter config only when it differs, and back up anything already
# there. A hand-edited greetd config must not silently vanish on a --force run.
write_greetd_config() {
  local config_file="${1:-$GREETD_CONFIG_DEFAULT}"
  local backup=""

  if [[ -f "$config_file" ]]; then
    # cmp, not diff: diffutils is not guaranteed on a Fedora Minimal install.
    if cmp -s <(_greetd_config_body) "$config_file"; then
      log_ok "greetd config already up to date: $config_file"
      return 0
    fi
    backup="${config_file}.tophat-backup.$(date '+%Y%m%dT%H%M%S%z')"
    cp -a -- "$config_file" "$backup"
    log_warn "Existing greeter config differed; backed up to $backup"
  fi

  _greetd_config_body >"$config_file"
  chmod 0644 "$config_file"
  log_ok "greetd configuration written: $config_file"
}

run_services_stage() {
  if stage_already_run "services"; then
    log_info "Services stage already completed; skipping"
    return 0
  fi

  # Ensure graphical target
  run_logged "Setting default target to graphical" \
    systemctl set-default graphical.target

  # DMS Greeter — root-driven non-interactive setup.
  # Avoid `dms greeter install` here because it shells out to sudo and
  # requires an interactive terminal/password prompt when run from this script.
  if [[ "$DRY_RUN" != true ]] && ! pkg_present "dms-greeter"; then
    log_error "dms-greeter is not installed. Cannot configure DMS Greeter."
    log_error "Run the packaging stage first, or run the full installer."
    exit 1
  fi

  run_logged "Creating greetd configuration directory" \
    mkdir -p /etc/greetd

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would write $GREETD_CONFIG_DEFAULT for DMS Greeter"
  else
    log_info "Writing $GREETD_CONFIG_DEFAULT for DMS Greeter"
    write_greetd_config "$GREETD_CONFIG_DEFAULT"
  fi

  # Make greetd unlock/start gnome-keyring during user login.
  # Without this, libsecret apps such as browsers may prompt to unlock
  # the login keyring after every graphical login.
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would configure /etc/pam.d/greetd for gnome-keyring"
  elif [[ -f /etc/pam.d/greetd ]]; then
    if grep -q "pam_gnome_keyring.so" /etc/pam.d/greetd; then
      log_ok "greetd PAM already includes gnome-keyring"
    else
      log_info "Adding gnome-keyring PAM hooks to greetd"
      cat >>/etc/pam.d/greetd <<'PAM_EOF'

# Unlock/start GNOME Keyring for graphical sessions
-auth optional pam_gnome_keyring.so
-session optional pam_gnome_keyring.so auto_start
-password optional pam_gnome_keyring.so use_authtok
PAM_EOF
      log_ok "greetd PAM configured for gnome-keyring"
    fi
  else
    log_warn "/etc/pam.d/greetd not found; cannot configure gnome-keyring PAM hooks"
  fi

  run_logged "Enabling greetd service" \
    systemctl enable greetd.service

  # PipeWire note — no system-level enable needed
  log_info "PipeWire services are user-session managed (auto-start on login)"

  log_ok "Services stage complete"
}
