# =============================================================================
#  run_logged.sh — Logging, error handling, and state tracking
#
#    log() → log_info() / log()
#    warn() → log_warn() / warn()
#    error_exit() → log_error() + exit 1
# =============================================================================

declare -A STAGE_STATUS
declare -A STAGE_DURATIONS
CURRENT_STAGE=""
SETUP_START_TIME=$(date +%s)

# -----------------------------------------------------------------------------
# Core log writer
# -----------------------------------------------------------------------------
_log_write() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  # Always write to log file
  echo "[$timestamp] [$level] $message" >>"$SETUP_LOG"

  # Print to terminal with colour based on verbosity
  if [[ "$VERBOSE" == true ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARN" ]] || [[ "$level" == "STAGE" ]]; then
    case "$level" in
    ERROR) echo -e "${CLR_RED}[ERROR]${CLR_RESET} $message" >&2 ;;
    WARN) echo -e "${CLR_YELLOW}[WARN]${CLR_RESET} $message" ;;
    INFO) echo -e "${CLR_BLUE}[INFO]${CLR_RESET} $message" ;;
    STAGE) echo -e "${CLR_BOLD}${CLR_GREEN}[STAGE]${CLR_RESET} $message" ;;
    OK) echo -e "${CLR_GREEN}[OK]${CLR_RESET} $message" ;;
    *) echo "[$level] $message" ;;
    esac
  fi
}

# v1-compatible aliases (so old habits still work)
log() { _log_write "INFO" "$1"; }
warn() { _log_write "WARN" "$1"; }
log_info() { _log_write "INFO" "$1"; }
log_warn() { _log_write "WARN" "$1"; }
log_error() { _log_write "ERROR" "$1"; }
log_ok() { _log_write "OK" "$1"; }

# v1-compatible error_exit
error_exit() {
  log_error "$1"
  exit 1
}

# -----------------------------------------------------------------------------
# run_logged — Execute a command with full logging
# -----------------------------------------------------------------------------
run_logged() {
  local description="$1"
  shift
  local cmd_str="$*"
  local start_time end_time duration

  log_info "$description"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${CLR_YELLOW}[DRY-RUN]${CLR_RESET} $cmd_str"
    return 0
  fi

  start_time=$(date +%s)

  local exit_code
  set +e
  if [[ "$VERBOSE" == true ]]; then
    "$@" 2>&1 | tee -a "$SETUP_LOG"
    exit_code=${PIPESTATUS[0]}
  else
    "$@" >>"$SETUP_LOG" 2>&1
    exit_code=$?
  fi
  set -e

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    log_ok "$description (${duration}s)"
  else
    log_error "$description FAILED (exit $exit_code, ${duration}s)"
    log_error "Command: $cmd_str"
    log_error "Check full log: $SETUP_LOG"
    exit "$exit_code"
  fi
}

# -----------------------------------------------------------------------------
# Stage-level tracking
# -----------------------------------------------------------------------------
log_stage_start() {
  CURRENT_STAGE="$1"
  _log_write "STAGE" "▶ Starting stage: $CURRENT_STAGE"
  STAGE_STATUS[$CURRENT_STAGE]="running"
  STAGE_DURATIONS[$CURRENT_STAGE]=$(date +%s)
}

log_stage_complete() {
  local stage="$1"

  if [[ "${STAGE_STATUS[$stage]:-}" == "skipped" ]]; then
    _log_write "STAGE" "↷ Skipped stage: $stage"
    return 0
  fi

  local start=${STAGE_DURATIONS[$stage]}
  local elapsed=$(($(date +%s) - start))
  STAGE_STATUS[$stage]="complete"
  STAGE_DURATIONS[$stage]=$elapsed

  _log_write "STAGE" "✓ Completed stage: $stage (${elapsed}s)"

  if [[ "$DRY_RUN" != true ]]; then
    date '+%Y-%m-%d %H:%M:%S' >"$SETUP_STATE_DIR/stage-${stage}.done"
  fi
}

# -----------------------------------------------------------------------------
# Idempotency check
# -----------------------------------------------------------------------------
stage_already_run() {
  local stage="$1"
  if [[ -f "$SETUP_STATE_DIR/stage-${stage}.done" ]] && [[ "$FORCE" != true ]]; then
    STAGE_STATUS[$stage]="skipped"
    STAGE_DURATIONS[$stage]=0
    return 0
  fi
  return 1
}

# Mark a stage as intentionally skipped. log_stage_complete will then avoid
# writing a completion marker, allowing a later run to discover new opt-ins.
skip_stage() {
  local stage="$1"
  local reason="$2"
  STAGE_STATUS[$stage]="skipped"
  STAGE_DURATIONS[$stage]=0
  log_info "$reason"
}

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
log_summary() {
  local total_duration=$(($(date +%s) - SETUP_START_TIME))

  _log_write "STAGE" ""
  _log_write "STAGE" "══════════════════════════════════════════════════"
  _log_write "STAGE" "  SETUP SUMMARY"
  _log_write "STAGE" "══════════════════════════════════════════════════"

  for stage in "${STAGES[@]}"; do
    local status="${STAGE_STATUS[$stage]:-skipped}"
    local dur="${STAGE_DURATIONS[$stage]:-0}s"
    _log_write "STAGE" "  $stage: $status ($dur)"
  done

  _log_write "STAGE" ""
  _log_write "STAGE" "  Total time: ${total_duration}s"
  _log_write "STAGE" "  Log file: $SETUP_LOG"
  _log_write "STAGE" "  State dir: $SETUP_STATE_DIR"
  _log_write "STAGE" "══════════════════════════════════════════════════"

  if [[ "$DRY_RUN" != true ]]; then
    date '+%Y-%m-%d %H:%M:%S' >"$SETUP_STATE_DIR/.last-run"
  fi

  echo ""
  echo -e "${CLR_GREEN}Done.${CLR_RESET} Full log at ${CLR_BOLD}$SETUP_LOG${CLR_RESET}"
}
