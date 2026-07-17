# =============================================================================
#  services/all.sh — Configure system services for niri + DMS desktop
#
#  Note: PipeWire services are user-session units on Fedora. They start
#  automatically when the user logs in.
# =============================================================================

if stage_already_run "services"; then
    log_info "Services stage already completed; skipping"
else
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
        log_info "[DRY-RUN] Would write /etc/greetd/config.toml for DMS Greeter"
    else
        log_info "Writing /etc/greetd/config.toml for DMS Greeter"
        cat > /etc/greetd/config.toml <<'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
GREETD_EOF
        log_ok "greetd configuration written"
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
            cat >> /etc/pam.d/greetd <<'PAM_EOF'

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
fi
