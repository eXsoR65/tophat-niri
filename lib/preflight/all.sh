# =============================================================================
#  preflight/all.sh — Execution order
# =============================================================================

source "$SETUP_LIB/preflight/detect_env.sh"
source "$SETUP_LIB/preflight/detect_hardware.sh"

detect_environment
detect_hardware

if [[ -f "$SETUP_STATE_DIR/stage-preflight.done" && "$FORCE" != true ]]; then
    log_info "Preflight update already completed; skipping system update (use --force to re-run)"
else
    source "$SETUP_LIB/preflight/system_update.sh"
fi
