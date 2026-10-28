# =============================================================================
#  detect_env.sh — Gather system environment information
# =============================================================================

export FEDORA_VERSION=""
export ARCHITECTURE=""
export IS_ROOT=false
export NETWORK_OK=false
export SETUP_PREVIOUSLY_COMPLETED=false

# Fail fast and clearly on a non-Fedora host. Without this the next command
# (`rpm -E %fedora`) dies from `set -e` with "rpm: command not found", which
# reads like a Tophat bug rather than an unsupported system.
# Takes an explicit path so it can be tested without touching /etc/os-release.
require_fedora() {
  local os_release="${1:-/etc/os-release}"
  local detected="unknown"

  if [[ -r "$os_release" ]]; then
    detected="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$os_release" | head -1)"
    [[ -n "$detected" ]] || detected="unknown"
    if grep -qE '^ID="?fedora"?$' "$os_release"; then
      return 0
    fi
  fi

  log_error "Tophat only installs on Fedora. Detected: $detected"
  log_error "Nothing has been changed."
  exit 1
}

detect_environment() {
  log_info "Detecting system environment..."

  require_fedora /etc/os-release

  FEDORA_VERSION="$(rpm -E %fedora)"
  log_info "Fedora release: $FEDORA_VERSION"

  ARCHITECTURE="$(uname -m)"
  log_info "Architecture: $ARCHITECTURE"

  if is_root; then
    IS_ROOT=true
    log_ok "Running as root"
  else
    log_error "This script must be run as root or via sudo"
    log_error "Try: sudo $SETUP_ROOT/install.sh"
    exit 1
  fi

  # Network connectivity check
  log_info "Checking network connectivity..."
  if check_network_connectivity dl.fedoraproject.org; then
    export NETWORK_OK=true
    log_ok "Network is reachable"
  else
    export NETWORK_OK=false
    log_error "Cannot reach Fedora mirrors. Network may be down."
    exit 1
  fi

  # Resolve target user without guessing. Use --target-user or sudo from the
  # intended non-root account.
  if ! resolve_target_user "${TARGET_USER:-}"; then
    log_error "Could not resolve a non-root target user with a valid home directory"
    log_error "Run via sudo from the target account, or pass --target-user USER"
    exit 1
  fi

  log_ok "Target user: $TARGET_USER ($TARGET_USER_HOME)"

  # Previous completion check
  if [[ -f "$SETUP_STATE_DIR/.completed" ]]; then
    SETUP_PREVIOUSLY_COMPLETED=true
    if [[ "$FORCE" != true ]]; then
      log_warn "Tophat has already been completed on this system"
      log_warn "Use --force to re-run, or --select to run specific stages"
      log_warn "Continuing anyway in 5 seconds... (Ctrl+C to abort)"
      sleep 5
    fi
  fi

  log_ok "Environment detection complete"
}
