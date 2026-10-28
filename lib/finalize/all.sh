# =============================================================================
#  finalize/all.sh — Cleanup and completion marker
# =============================================================================

# Preview first (changes nothing), then remove only on an explicit decision.
autoremove_orphans() {
  log_info "Previewing the packages dnf would autoremove (no changes yet)"
  dnf autoremove --assumeno >>"$SETUP_LOG" 2>&1 || true
  run_logged "Autoremoving orphaned packages" dnf autoremove -y
}

run_finalize_stage() {
  if stage_already_run "finalize"; then
    log_info "Finalize stage already completed; skipping"
    return 0
  fi

  # Guard: never mark a system complete while earlier stages have not run.
  # A false .completed marker would mislead every later run, so --force does
  # not bypass this. Extras is excluded because it is intentionally
  # marker-less when no opt-ins are enabled.
  if [[ "$DRY_RUN" != true ]]; then
    local missing_stages=()
    local required_stage
    for required_stage in preflight repos packaging config services; do
      if [[ ! -f "$SETUP_STATE_DIR/stage-${required_stage}.done" ]]; then
        missing_stages+=("$required_stage")
      fi
    done

    if [[ ${#missing_stages[@]} -gt 0 ]]; then
      local missing_csv
      missing_csv="$(
        IFS=,
        echo "${missing_stages[*]}"
      )"
      log_error "Refusing to finalize: incomplete stages: ${missing_stages[*]}"
      log_error "Run them first (--select $missing_csv)"
      exit 1
    fi
  fi

  # Defensive defaults (needed when preflight was skipped)
  FEDORA_VERSION="${FEDORA_VERSION:-unknown}"
  GPU_VENDOR="${GPU_VENDOR:-unknown}"
  FORM_FACTOR="${FORM_FACTOR:-unknown}"
  HAS_INTEL_WIFI="${HAS_INTEL_WIFI:-unknown}"
  TARGET_USER="${TARGET_USER:-unknown}"
  NIRI_COPR="${NIRI_COPR:-yalter/niri}"
  DMS_COPR="${DMS_COPR:-avengemedia/dms}"

  # Clean up DNF cache
  run_logged "Cleaning DNF cache" dnf clean packages

  # `dnf autoremove` removes anything the solver considers unneeded, which can
  # be more than the replacement list. That is destructive and system-wide, so
  # it follows the same consent rule as pkg_remove() instead of always running.
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would preview orphaned packages and remove them only on consent"
  elif [[ "${ACCEPT_PACKAGE_REMOVALS:-false}" == true ]]; then
    autoremove_orphans
  elif [[ -t 0 ]]; then
    log_warn "dnf autoremove removes packages the solver considers unneeded,"
    log_warn "which can be more than the replacement list."
    printf 'Run dnf autoremove now? [y/N] '
    local answer=""
    read -r answer
    case "$answer" in
      y | Y | yes | YES) autoremove_orphans ;;
      *) log_warn "Skipped automatic package removal; run 'sudo dnf autoremove' yourself if wanted" ;;
    esac
  else
    log_warn "Skipping automatic package removal (needs --accept-package-removals or a TTY)"
  fi

  # Write completion marker
  if [[ "$DRY_RUN" != true ]]; then
    {
      date '+%Y-%m-%d %H:%M:%S'
      echo "version=$TOPHAT_VERSION"
      echo "fedora=$FEDORA_VERSION"
      echo "gpu=$GPU_VENDOR"
      echo "form_factor=$FORM_FACTOR"
      echo "intel_wifi=$HAS_INTEL_WIFI"
      echo "user=$TARGET_USER"
      echo "niri_copr=$NIRI_COPR"
      echo "dms_copr=$DMS_COPR"
    } >"$SETUP_STATE_DIR/.completed"
  fi

  log_ok "Tophat setup complete!"
  log_info "A reboot is recommended before starting your niri + DMS session"
  log_info "After first graphical login, run: dms setup && dms greeter sync"
  log_info "State files: $SETUP_STATE_DIR"
  log_info "Full log: $SETUP_LOG"
}
