# =============================================================================
#  run_logged.sh — Logging, error handling, and state tracking
#
#    log() → log_info() / log()
#    warn() → log_warn() / warn()
#    error_exit() → log_error() + exit 1
# =============================================================================

declare -gA STAGE_STATUS
declare -gA STAGE_DURATIONS
TOPHAT_FAILURE_REASON=""
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
  TOPHAT_FAILURE_REASON="$1"
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
  event_emit command desc="$description" stage="${CURRENT_STAGE:-}"

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
    TOPHAT_FAILURE_REASON="$description"
    exit "$exit_code"
  fi
}

# -----------------------------------------------------------------------------
# Structured events (for the TUI)
# -----------------------------------------------------------------------------
# With TOPHAT_TUI=1 the installer appends one JSON object per line to
# $SETUP_STATE_DIR/events.ndjson, so a front end can render a stage board
# without parsing the human log. Deliberately dependency-free: string
# substitutions and an append, no jq and no python.

_json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  # Bash strings cannot contain NUL; escape every other JSON control byte,
  # including backspace, form feed and terminal escape sequences.
  local code char escaped
  for ((code = 1; code < 32; code++)); do
    printf -v escaped '\\u%04x' "$code"
    printf -v char '%b' "$escaped"
    s=${s//"$char"/"$escaped"}
  done
  printf '%s' "$s"
}

tophat_events_file() {
  printf '%s' "${TOPHAT_EVENTS_FILE:-$SETUP_STATE_DIR/events.ndjson}"
}

# A dry run must never reset the live stream or create the live state directory.
# Keep the generated path in the parent shell so every event uses the same file.
_tophat_events_prepare() {
  if [[ "${DRY_RUN:-false}" == true && -z "${TOPHAT_EVENTS_FILE:-}" ]]; then
    TOPHAT_EVENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/tophat-events.XXXXXXXX.ndjson")" || return 1
    export TOPHAT_EVENTS_FILE
  fi
  local file
  file="$(tophat_events_file)"
  mkdir -p -- "$(dirname -- "$file")"
}

# Start a clean event stream for this run. Events are observational: neither
# path creation nor a failed write may change installation success/failure.
tophat_events_reset() {
  [[ "${TOPHAT_TUI:-0}" == 1 ]] || return 0
  _tophat_events_prepare 2>/dev/null || return 0
  { : >"$(tophat_events_file)"; } 2>/dev/null || true
}

# event_emit <type> [key=value ...]
event_emit() {
  [[ "${TOPHAT_TUI:-0}" == 1 ]] || return 0

  local type="$1"
  shift
  local line pair key value
  line="{\"event\":\"$(_json_escape "$type")\",\"at\":${EPOCHSECONDS:-$(date +%s)}"

  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    line+=",\"$(_json_escape "$key")\":\"$(_json_escape "$value")\""
  done
  line+="}"

  _tophat_events_prepare 2>/dev/null || return 0
  { printf '%s\n' "$line" >>"$(tophat_events_file)"; } 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Stage-level tracking
# -----------------------------------------------------------------------------
log_stage_start() {
  CURRENT_STAGE="$1"
  _log_write "STAGE" "▶ Starting stage: $CURRENT_STAGE"
  event_emit stage_start stage="$CURRENT_STAGE"
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
  event_emit stage_done stage="$stage" seconds="$elapsed"

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
    intel-wifi.packages remove-replaced.packages applications.packages \
    flatpaks.packages homebrew.packages distrobox.enable; do
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
  event_emit marker stage="$stage"
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

  skip_stage "$stage" "Stage '$stage' already completed (matching marker)"
  return 0
}

# Mark a stage as intentionally skipped. log_stage_complete will then avoid
# writing a completion marker, allowing a later run to discover new opt-ins.
skip_stage() {
  local stage="$1"
  local reason="$2"
  STAGE_STATUS[$stage]="skipped"
  event_emit stage_skipped stage="$stage" reason="$reason"
  STAGE_DURATIONS[$stage]=0
  log_info "$reason"
}

# -----------------------------------------------------------------------------
# Composable exit handlers
# -----------------------------------------------------------------------------
# Anything that needs cleanup on exit must register here. Installing a bare
# `trap ... EXIT` replaces every other handler: Homebrew's temp-file cleanup did
# exactly that and silently dropped the lock's cleanup, leaving a stale lock
# behind after a successful run.
# Global on purpose (-g): install.sh sources the helpers from inside main(), so a
# plain `declare` here would be scoped to main() - and the EXIT trap runs after
# main() has returned, where that binding no longer exists. Under `set -u` the
# trap then dies with "unbound variable" and no cleanup handler runs at all,
# leaving the run lock behind after a successful install.
declare -ga _EXIT_HANDLERS=()

register_exit_handler() {
  _EXIT_HANDLERS+=("$1")
  trap '_run_exit_handlers "$?"' EXIT
}

_run_exit_handlers() {
  local rc="$1" handler

  # Every handler sees the original status, never the previous cleanup's status.
  # A failing cleanup must not prevent the other handlers or replace that status.
  if [[ -n "${_EXIT_HANDLERS[*]:-}" ]]; then
    for handler in "${_EXIT_HANDLERS[@]}"; do
      "$handler" "$rc" || true
    done
  fi
  return "$rc"
}

_tophat_final_failure() {
  local rc="$1"
  [[ "$rc" -ne 0 && -n "${CURRENT_STAGE:-}" ]] || return 0
  STAGE_STATUS[$CURRENT_STAGE]="failed"
  event_emit stage_fail stage="$CURRENT_STAGE" \
    reason="${TOPHAT_FAILURE_REASON:-Installer exited with status $rc}" exit="$rc"
}

# Includes explicit exit, raw set -e failures, and failures propagated out of
# main(). One terminal failure event, composed with lock and temporary cleanup.
register_exit_handler _tophat_final_failure

# -----------------------------------------------------------------------------
# Single-run lock
# -----------------------------------------------------------------------------
# mkdir is atomic and, unlike flock(1), always available on a Fedora Minimal
# install. The pid file lets a lock left behind by a killed run be recognised as
# stale instead of blocking the machine forever.
acquire_run_lock() {
  local lock_dir="$SETUP_STATE_DIR/.lock.d"
  local pid_file="$lock_dir/pid"

  mkdir -p "$SETUP_STATE_DIR"

  # Exactly one mechanism, on purpose. Two backends cannot exclude each other:
  # a run that starts before util-linux is installed would hold the directory
  # lock while a later run, now seeing flock, takes a different lock file.
  # mkdir is atomic, needs nothing beyond the shell, and is available before any
  # package is installed.
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$pid_file"
    RUN_LOCK_DIR="$lock_dir"
    register_exit_handler release_run_lock
    return 0
  fi

  if [[ -r "$pid_file" ]]; then
    local existing_pid
    existing_pid="$(<"$pid_file")"
    existing_pid="${existing_pid//[[:space:]]/}"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      log_error "Another Tophat run is in progress (pid $existing_pid, lock: $lock_dir)"
      log_error "Wait for it to finish."
      return 1
    fi
  fi

  # Deliberately never reclaimed automatically: reclaiming races with acquiring.
  log_error "A lock directory is in the way and its owner is not running: $lock_dir"
  log_error "If no Tophat run is active, remove it and retry: rm -rf '$lock_dir'"
  return 1
}

release_run_lock() {
  [[ -n "${RUN_LOCK_DIR:-}" ]] || return 0
  rm -rf -- "$RUN_LOCK_DIR"
  RUN_LOCK_DIR=""
  return 0
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
