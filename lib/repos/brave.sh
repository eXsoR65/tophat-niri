# =============================================================================
#  brave.sh — Enable the official Brave Browser RPM repository
# =============================================================================

if [[ "${NETWORK_OK:-false}" != true ]]; then
  log_warn "Skipping Brave repository — no network"
  return 0
fi

BRAVE_REPO_FILE="/etc/yum.repos.d/brave-browser.repo"
BRAVE_REPO_URL="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

if [[ -f "$BRAVE_REPO_FILE" ]] || dnf repolist --all 2>/dev/null | grep -qi '^brave-browser\b'; then
  log_ok "Brave Browser repository already enabled"
else
  if ! dnf config-manager --help &>/dev/null; then
    run_logged "Installing DNF config-manager plugin" dnf install -y dnf-plugins-core
  fi

  run_logged "Enabling Brave Browser repository" \
    dnf config-manager addrepo --from-repofile="$BRAVE_REPO_URL"
fi
