#!/bin/bash
# =============================================================================
#  Tophat v2.1 — Fedora niri workstation installer
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
# Argument Parsing
# -----------------------------------------------------------------------------
DRY_RUN=false
SELECTIVE_STAGES=""
FORCE=false
VERBOSE=false
ACCEPT_PACKAGE_REMOVALS=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Transforms a base Fedora install into a niri + DMS workstation.

Options:
  --dry-run          Print what would happen without executing changes
  --select STAGES   Comma-separated list of stages to run
                     (e.g.: repos,packaging,config)
  --target-user USER Configure this non-root user account
  --accept-package-removals
                     Allow Tophat to remove packages listed as replaced
  --force            Run even if setup marker indicates completion
  --verbose          Show command output inline (don't suppress)
  --help             Show this message

Available stages:
  preflight, repos, packaging, config, services, extras, finalize
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --select)
      if [[ $# -lt 2 || "${2:0:2}" == "--" ]]; then
        echo "Error: --select requires a comma-separated stage list" >&2
        exit 1
      fi
      SELECTIVE_STAGES="$2"
      shift 2
      ;;
    --target-user)
      if [[ $# -lt 2 || "${2:0:2}" == "--" ]]; then
        echo "Error: --target-user requires a username" >&2
        exit 1
      fi
      TARGET_USER="$2"
      shift 2
      ;;
    --accept-package-removals)
      ACCEPT_PACKAGE_REMOVALS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help | -h) usage ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

export DRY_RUN FORCE VERBOSE ACCEPT_PACKAGE_REMOVALS

# All stages in execution order
ALL_STAGES=("preflight" "repos" "packaging" "config" "services" "extras" "finalize")
declare -Ar STAGE_DEPENDENCIES=(
  [preflight]=""
  [repos]="preflight"
  [packaging]="preflight repos"
  [config]="preflight packaging"
  [services]="preflight packaging config"
  [extras]="preflight"
  [finalize]="preflight"
)

declare -A STAGE_WANTED=()
declare -A STAGE_RESOLVING=()

stage_exists() {
  local candidate="$1"
  local stage

  for stage in "${ALL_STAGES[@]}"; do
    [[ "$candidate" == "$stage" ]] && return 0
  done

  return 1
}

stage_add_with_dependencies() {
  local stage="$1"
  local dep

  if ! stage_exists "$stage"; then
    echo "Error: invalid stage '$stage'" >&2
    echo "Available stages: ${ALL_STAGES[*]}" >&2
    exit 1
  fi

  # Already resolved in this run; its dependencies were processed too
  if [[ -n "${STAGE_WANTED[$stage]:-}" ]]; then
    return 0
  fi

  # Fail loudly if STAGE_DEPENDENCIES ever gains a cycle
  if [[ -n "${STAGE_RESOLVING[$stage]:-}" ]]; then
    echo "Error: circular stage dependency detected at '$stage'" >&2
    exit 1
  fi

  STAGE_RESOLVING[$stage]=1
  for dep in ${STAGE_DEPENDENCIES[$stage]}; do
    stage_add_with_dependencies "$dep"
  done
  unset 'STAGE_RESOLVING[$stage]'

  STAGE_WANTED[$stage]=1
}

if [[ -n "$SELECTIVE_STAGES" ]]; then
  IFS=',' read -ra SELECTED <<<"$SELECTIVE_STAGES"

  for sel in "${SELECTED[@]}"; do
    sel="${sel#"${sel%%[![:space:]]*}"}"
    sel="${sel%"${sel##*[![:space:]]}"}"

    if [[ -z "$sel" ]]; then
      echo "Error: --select contains an empty stage name" >&2
      exit 1
    fi

    stage_add_with_dependencies "$sel"
  done

  STAGES=()
  for stage in "${ALL_STAGES[@]}"; do
    [[ -n "${STAGE_WANTED[$stage]:-}" ]] && STAGES+=("$stage")
  done

  echo "Requested stages: ${SELECTED[*]}"
  echo "Execution plan: ${STAGES[*]}"
else
  STAGES=("${ALL_STAGES[@]}")
fi

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
