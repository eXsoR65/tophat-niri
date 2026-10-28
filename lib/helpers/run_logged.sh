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
    stage_marker_write "$stage"
  fi
}

# -----------------------------------------------------------------------------
# Idempotency: markers record *what* was completed, so they can be invalidated
# -----------------------------------------------------------------------------
# The configuration a stage depends on. Compared verbatim rather than hashed:
# sha256sum/cksum are not guaranteed on a Fedora Minimal install, and these
# files are a few KB.
_tophat_config_snapshot() {
  local base="${SETUP_PACKAGES:-}"
  local name file

  if [[ -z "$base" ]]; then
    printf '#no package directory\n'
    return 0
  fi

  for name in base-utils.packages desktop-support.packages dms-companions.packages \
    intel-wifi.packages applications.packages flatpaks.packages homebrew.packages \
    distrobox.enable; do
    file="$base/$name"
    printf '### %s\n' "$name"
    if [[ -r "$file" ]]; then
      cat -- "$file"
    else
      printf '#absent\n'
    fi
  done
}

# Write the completion marker plus the configuration it was completed with.
# Used by log_stage_complete and by the test suite.
stage_marker_write() {
  local stage="$1"

  mkdir -p "$SETUP_STATE_DIR"
  {
    printf 'completed=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'version=%s\n' "${TOPHAT_VERSION:-unknown}"
    printf 'user=%s\n' "${TARGET_USER:-unknown}"
  } >"$SETUP_STATE_DIR/stage-${stage}.done"
  _tophat_config_snapshot >"$SETUP_STATE_DIR/stage-${stage}.config"
}

_marker_field() {
  local file="$1" key="$2" line

  while IFS= read -r line; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <"$file"
  return 1
}

stage_already_run() {
  local stage="$1"
  local marker="$SETUP_STATE_DIR/stage-${stage}.done"
  local snapshot="$SETUP_STATE_DIR/stage-${stage}.config"
  local recorded

  [[ -f "$marker" ]] || return 1
  [[ "${FORCE:-false}" == true ]] && return 1

  if [[ -n "${TOPHAT_VERSION:-}" ]]; then
    recorded="$(_marker_field "$marker" version || true)"
    if [[ -n "$recorded" && "$recorded" != "$TOPHAT_VERSION" ]]; then
      log_info "Stage '$stage' ran under v$recorded; re-running under v$TOPHAT_VERSION"
      return 1
    fi
  fi

  if [[ -n "${TARGET_USER:-}" ]]; then
    recorded="$(_marker_field "$marker" user || true)"
    if [[ -n "$recorded" && "$recorded" != "$TARGET_USER" ]]; then
      log_info "Stage '$stage' ran for user '$recorded'; re-running for '$TARGET_USER'"
      return 1
    fi
  fi

  if [[ ! -f "$snapshot" ]]; then
    log_info "Stage '$stage' has no recorded configuration; re-running so one is stored"
    return 1
  fi

  if [[ "$(<"$snapshot")" != "$(_tophat_config_snapshot)" ]]; then
    log_info "Package selection changed since stage '$stage' ran; re-running it"
    return 1
  fi

  STAGE_STATUS[$stage]="skipped"
  STAGE_DURATIONS[$stage]=0
  return 0
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
# Single-run lock
# -----------------------------------------------------------------------------
# mkdir is atomic and, unlike flock(1), always available on a Fedora Minimal
# install. The pid file lets a lock left behind by a killed run be recognised as
# stale instead of blocking the machine forever.
acquire_run_lock() {
  local lock_dir="$SETUP_STATE_DIR/.lock.d"
  local pid_file="$lock_dir/pid"
  local claim_dir="$SETUP_STATE_DIR/.lock.stale.$$"
  local existing_pid="" attempt

  mkdir -p "$SETUP_STATE_DIR"

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$pid_file"
    RUN_LOCK_DIR="$lock_dir"
    trap 'release_run_lock' EXIT
    return 0
  fi

  # The owner creates the directory before it can publish its pid, so a missing
  # pid file is not evidence that the owner is gone. Give it a moment: without
  # this, two installers starting at the same instant both acquire the lock.
  for ((attempt = 0; attempt < 30; attempt++)); do
    if [[ -r "$pid_file" ]]; then
      existing_pid="$(<"$pid_file")"
      # Defend against a hand-edited or truncated pid file.
      existing_pid="${existing_pid//[[:space:]]/}"
      [[ -n "$existing_pid" ]] && break
    fi
    sleep 0.1
  done

  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    log_error "Another Tophat run is in progress (pid $existing_pid, lock: $lock_dir)"
    log_error "Wait for it to finish, or remove $lock_dir if you are sure it is dead."
    return 1
  fi

  # Reclaiming a stale lock must have exactly one winner: rename it away first,
  # and only the process whose rename succeeds may create the replacement.
  if ! mv -- "$lock_dir" "$claim_dir" 2>/dev/null; then
    log_error "Another Tophat run is reclaiming a stale lock; retry in a moment"
    return 1
  fi
  rm -rf -- "$claim_dir"

  log_warn "Breaking stale Tophat lock (pid ${existing_pid:-unknown} is gone)"
  mkdir "$lock_dir" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$pid_file"
  RUN_LOCK_DIR="$lock_dir"
  trap 'release_run_lock' EXIT
  return 0
}

release_run_lock() {
  [[ -n "${RUN_LOCK_DIR:-}" ]] || return 0
  rm -rf -- "$RUN_LOCK_DIR"
  RUN_LOCK_DIR=""
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
