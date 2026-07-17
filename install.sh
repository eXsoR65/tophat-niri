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

export TOPHAT_VERSION="2.1"
export SETUP_ROOT="$SCRIPT_DIR"
export SETUP_LIB="$SETUP_ROOT/lib"
export SETUP_FILES="$SETUP_ROOT/files"
export SETUP_PACKAGES="$SETUP_ROOT/packages"

# Logging and state
export SETUP_LOG="/var/log/tophat.log"
export SETUP_STATE_DIR="/var/lib/tophat"

# Target user (detected dynamically in preflight, fallback to 'x')
TARGET_USER="${SUDO_USER:-${USER:-x}}"

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

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Transforms a base Fedora install into a niri + DMS workstation.

Options:
  --dry-run          Print what would happen without executing changes
  --select STAGES   Comma-separated list of stages to run
                     (e.g.: repos,packaging,config)
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

export DRY_RUN FORCE VERBOSE

# All stages in execution order
ALL_STAGES=("preflight" "repos" "packaging" "config" "services" "extras" "finalize")

if [[ -n "$SELECTIVE_STAGES" ]]; then
  IFS=',' read -ra SELECTED <<<"$SELECTIVE_STAGES"

  for sel in "${SELECTED[@]}"; do
    valid=false
    for stage in "${ALL_STAGES[@]}"; do
      if [[ "$sel" == "$stage" ]]; then
        valid=true
        break
      fi
    done

    if [[ "$valid" != true ]]; then
      echo "Error: invalid stage '$sel'" >&2
      echo "Available stages: ${ALL_STAGES[*]}" >&2
      exit 1
    fi
  done

  STAGES=()
  for stage in "${ALL_STAGES[@]}"; do
    for sel in "${SELECTED[@]}"; do
      [[ "$stage" == "$sel" ]] && STAGES+=("$stage")
    done
  done
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
banner() {
  local start_date
  start_date="$(date '+%Y-%m-%d %H:%M:%S')"

  echo -e "${CLR_BOLD}"
  echo "════════════════════════════════════════════════════════════"
  echo "          Tophat v${TOPHAT_VERSION}                         "
  echo "          Fedora niri + DankMaterialShell                   "
  echo "════════════════════════════════════════════════════════════"
  echo "  Started: ${start_date}                                    "
  if [[ "$DRY_RUN" == true ]]; then
    echo "  Mode: DRY RUN (no changes will be made)                 "
  else
    echo "  Mode: LIVE                                              "
  fi
  echo "  Stages: ${STAGES[*]}                                      "
  echo "════════════════════════════════════════════════════════════"
  echo -e "${CLR_RESET}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
trap 'rc=$?; if declare -F log_error >/dev/null; then log_error "Tophat failed at line $LINENO (exit code $rc)"; else echo "[ERROR] Tophat failed at line $LINENO (exit code $rc)" >&2; fi' ERR

main() {
  banner

  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$SETUP_STATE_DIR"
  fi

  echo "=== Tophat v${TOPHAT_VERSION} — $(date) ===" >"$SETUP_LOG"
  echo "Dry run: $DRY_RUN | Stages: ${STAGES[*]}" >>"$SETUP_LOG"

  # Helpers are always loaded first
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
    source "$stage_file"
    log_stage_complete "$stage"
  done

  log_summary
}

main "$@"
