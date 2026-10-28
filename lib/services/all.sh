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
  local config_dir tmp backup=""

  config_dir="$(dirname -- "$config_file")"

  if [[ -f "$config_file" ]]; then
    # Plain string comparison: neither diff nor cmp is guaranteed on a Fedora
    # Minimal install (the fedora container ships coreutils-single, no cmp).
    if [[ "$(_greetd_config_body)" == "$(<"$config_file")" ]]; then
      log_ok "greetd config already up to date: $config_file"
      return 0
    fi
    backup="${config_file}.tophat-backup.$(date '+%Y%m%dT%H%M%S%z')"
    cp -a -- "$config_file" "$backup"
    log_warn "Existing greeter config differed; backed up to $backup"
  fi

  # Write beside the target and rename: a half-written greeter config would
  # leave the machine unable to start a graphical session.
  tmp="$(mktemp "${config_dir}/.tophat-greetd.XXXXXX")"
  _greetd_config_body >"$tmp"
  chmod 0644 "$tmp"
  mv -f -- "$tmp" "$config_file"
  log_ok "greetd configuration written: $config_file"
}

# ---- 2. PAM hooks: per-hook verification, backup, atomic replace ---------
PAM_FILE_DEFAULT="/etc/pam.d/greetd"

_pam_required_hooks() {
  printf '%s\n' \
    '-auth optional pam_gnome_keyring.so' \
    '-session optional pam_gnome_keyring.so auto_start' \
    '-password optional pam_gnome_keyring.so use_authtok'
}

# Appends only the hooks that are actually missing, after backing the file up.
# Checking one generic reference is not enough: a PAM file can mention
# pam_gnome_keyring.so on the auth line and still fail to auto-start the keyring.
ensure_pam_keyring_hooks() {
  local pam_file="${1:-$PAM_FILE_DEFAULT}"
  local hook backup tmp missing=()

  if [[ ! -f "$pam_file" ]]; then
    log_warn "$pam_file not found; cannot configure gnome-keyring PAM hooks"
    return 0
  fi

  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    grep -qF -- "$hook" "$pam_file" || missing+=("$hook")
  done <<<"$(_pam_required_hooks)"

  if ((${#missing[@]} == 0)); then
    log_ok "greetd PAM already has all gnome-keyring hooks"
    return 0
  fi

  backup="${pam_file}.tophat-backup.$(date '+%Y%m%dT%H%M%S%z')"
  cp -a -- "$pam_file" "$backup"
  log_warn "Backed up $pam_file to $backup before adding ${#missing[@]} hook(s)"

  tmp="$(mktemp "$(dirname -- "$pam_file")/.tophat-pam.XXXXXX")"
  cat -- "$pam_file" >"$tmp"
  {
    printf '\n# Unlock/start GNOME Keyring for graphical sessions (added by Tophat)\n'
    printf '%s\n' "${missing[@]}"
  } >>"$tmp"
  chmod 0644 "$tmp"
  mv -f -- "$tmp" "$pam_file"

  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    grep -qF -- "$hook" "$pam_file" ||
      log_error "PAM hook still missing after write: $hook"
  done <<<"$(_pam_required_hooks)"
  log_ok "greetd PAM configured for gnome-keyring (${#missing[@]} hooks added)"
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
    log_info "[DRY-RUN] Would ensure gnome-keyring PAM hooks in $PAM_FILE_DEFAULT"
  else
    ensure_pam_keyring_hooks "$PAM_FILE_DEFAULT"
  fi

  run_logged "Enabling greetd service" \
    systemctl enable greetd.service

  # PipeWire note — no system-level enable needed
  log_info "PipeWire services are user-session managed (auto-start on login)"

  log_ok "Services stage complete"
}
