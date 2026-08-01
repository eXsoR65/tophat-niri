#!/bin/bash
# =============================================================================
#  Tophat v2.2 — Fedora niri workstation installer
#  Transforms a base Fedora installation into a fully configured workstation
#  running niri + DankMaterialShell.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SETUP_ROOT="$SCRIPT_DIR"
TOPHAT_VERSION="$(<"$SETUP_ROOT/VERSION")"
readonly TOPHAT_VERSION
export TOPHAT_VERSION
export SETUP_LIB="$SETUP_ROOT/lib"
export SETUP_PACKAGES="$SETUP_ROOT/packages"

# Logging and state
export SETUP_LOG_DIR="/var/log/tophat"
export SETUP_LOG=""
export SETUP_STATE_DIR="/var/lib/tophat"

# Target user (resolved during preflight)
TARGET_USER=""

# COPR repositories (stable only)
NIRI_COPR="yalter/niri"
DMS_COPR="avengemedia/dms"
GHOSTTY_COPR="scottames/ghostty"

export NIRI_COPR DMS_COPR GHOSTTY_COPR TARGET_USER SETUP_ROOT SETUP_LIB

# Colours for terminal output (disabled if not a TTY)
if [[ -t 1 ]]; then
  export CLR_RED='\033[0;31m'
  export CLR_GREEN='\033[0;32m'
  export CLR_YELLOW='\033[0;33m'
  export CLR_BLUE='\033[0;34m'
  export CLR_BOLD='\033[1m'
  export CLR_RESET='\033[0m'
else
  export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
fi

# -----------------------------------------------------------------------------
# Stage registry and argument parsing
# -----------------------------------------------------------------------------

# shellcheck source=lib/stages.sh
source "$SETUP_LIB/stages.sh"

parse_args "$@"

resolve_stages

# -----------------------------------------------------------------------------
# Early privilege check
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root or via sudo" >&2
  echo "Try: sudo $SCRIPT_DIR/install.sh" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
BANNER_WIDTH=60

_banner_line() {
  printf "%-${BANNER_WIDTH}s\n" "$1"
}

_banner_center() {
  local text="$1"
  local pad_left=$(((BANNER_WIDTH - ${#text}) / 2))
  local pad_right=$((BANNER_WIDTH - pad_left - ${#text}))
  ((pad_left < 0)) && pad_left=0
  ((pad_right < 0)) && pad_right=0
  printf "%${pad_left}s%s%${pad_right}s\n" "" "$text" ""
}

_banner_separator() {
  printf '═%.0s' $(seq "$BANNER_WIDTH")
  printf '\n'
}

banner() {
  local start_date
  start_date="$(date '+%Y-%m-%d %H:%M:%S')"

  local mode_line="  Mode: LIVE"
  if [[ "$DRY_RUN" == true ]]; then
    mode_line="  Mode: DRY RUN (no changes will be made)"
  fi

  echo -e "${CLR_BOLD}"
  _banner_separator
  _banner_center "Tophat v${TOPHAT_VERSION}"
  _banner_center "Fedora niri + DankMaterialShell"
  _banner_separator
  _banner_line "  Started: ${start_date}"
  _banner_line "$mode_line"
  _banner_line "  Stages: ${STAGES[*]}"
  _banner_separator
  echo -e "${CLR_RESET}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
on_error() {
  local rc=$?
  local line=${BASH_LINENO[0]:-unknown}

  if declare -F log_error >/dev/null; then
    log_error "Tophat failed at line $line (exit code $rc)"
  else
    echo "[ERROR] Tophat failed at line $line (exit code $rc)" >&2
  fi

  exit "$rc"
}

trap on_error ERR

main() {
  umask 027

  local run_id
  run_id="$(date '+%Y%m%dT%H%M%S%z')"

  if [[ "$DRY_RUN" == true ]]; then
    SETUP_LOG="${TMPDIR:-/tmp}/tophat-dry-run.$$.log"
  else
    install -d -m 0750 "$SETUP_STATE_DIR"
    install -d -m 0750 "$SETUP_LOG_DIR/runs"
    SETUP_LOG="$SETUP_LOG_DIR/runs/${run_id}.log"
    ln -sfn "runs/${run_id}.log" "$SETUP_LOG_DIR/latest.log"
  fi
  export SETUP_LOG

  printf '=== Tophat v%s — %s ===\n' "$TOPHAT_VERSION" "$(date)" >"$SETUP_LOG"
  printf 'Dry run: %s | Stages: %s\n' "$DRY_RUN" "${STAGES[*]}" >>"$SETUP_LOG"
  chmod 0640 "$SETUP_LOG" 2>/dev/null || true

  banner

  # Helpers are always loaded first
  # shellcheck source=lib/helpers/all.sh
  source "$SETUP_LIB/helpers/all.sh"
  log_ok "Helpers loaded"

  # Run each selected stage
  for stage in "${STAGES[@]}"; do
    local stage_file="$SETUP_LIB/$stage/all.sh"
    if [[ ! -f "$stage_file" ]]; then
      log_error "Stage file not found: $stage_file"
      exit 1
    fi

    log_stage_start "$stage"
    # shellcheck disable=SC1090
    source "$stage_file"

    local stage_entrypoint="run_${stage}_stage"
    if ! declare -F "$stage_entrypoint" >/dev/null; then
      log_error "Stage entry point not found: $stage_entrypoint"
      exit 1
    fi

    "$stage_entrypoint"
    log_stage_complete "$stage"
  done

  log_summary
}

main "$@"
