# =============================================================================
#  pkg.sh — Package management wrappers
#
#    pkg_install(), pkg_remove(), enable_copr()
#    + new repo_enable_rpm_fusion() for your request
# =============================================================================

# -----------------------------------------------------------------------------
# pkg_install — Install one or more packages (skips already-installed)
# -----------------------------------------------------------------------------
pkg_install() {
  local pkgs=("$@")
  local desc="Installing packages: ${pkgs[*]}"
  local to_install=()

  for pkg in "${pkgs[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      log_info "Already installed: $pkg"
    else
      to_install+=("$pkg")
    fi
  done

  if [[ ${#to_install[@]} -eq 0 ]]; then
    log_ok "All packages already installed"
    return 0
  fi

  run_logged "$desc" dnf install -y "${to_install[@]}"
}

# -----------------------------------------------------------------------------
# pkg_install_from_list — Install from a .packages file
# -----------------------------------------------------------------------------
pkg_install_from_list() {
  local list_file="$1"
  local pkgs=()

  if [[ ! -f "$list_file" ]]; then
    log_error "Package list not found: $list_file"
    return 1
  fi

  if ! read_list_file "$list_file" pkgs; then
    log_error "Could not read package list: $list_file"
    return 1
  fi

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log_warn "No packages found in $list_file"
    return 0
  fi

  log_info "Loading ${#pkgs[@]} packages from $(basename "$list_file")"
  pkg_install "${pkgs[@]}"
}

# -----------------------------------------------------------------------------
# pkg_remove — Remove one or more packages (skips already-absent)
# -----------------------------------------------------------------------------
pkg_remove() {
  local pkgs=("$@")
  local to_remove=()
  local pkg=""

  for pkg in "${pkgs[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      to_remove+=("$pkg")
    fi
  done

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    log_ok "Nothing to remove (already absent)"
    return 0
  fi

  log_warn "Tophat is about to remove packages. Package removal is destructive."
  log_warn "Packages selected for removal: ${to_remove[*]}"

  if [[ "$DRY_RUN" == true ]]; then
    run_logged "Would remove packages: ${to_remove[*]}" dnf remove -y "${to_remove[@]}"
    return 0
  fi

  if [[ "${ACCEPT_PACKAGE_REMOVALS:-false}" != true ]]; then
    if [[ -t 0 ]]; then
      local answer=""
      printf 'Continue removing these packages? [y/N] '
      read -r answer
      case "$answer" in
      y | Y | yes | YES) ;;
      *)
        log_error "Package removal declined"
        return 1
        ;;
      esac
    else
      log_error "Package removal requires confirmation"
      log_error "Re-run with --accept-package-removals to allow this non-interactively"
      return 1
    fi
  fi

  run_logged "Removing packages: ${to_remove[*]}" dnf remove -y "${to_remove[@]}"

  local manifest_dir="$SETUP_STATE_DIR/manifests"
  local manifest=""
  manifest="$manifest_dir/removed-packages-$(date '+%Y%m%dT%H%M%S%z').txt"
  install -d -m 0750 "$manifest_dir"
  printf '%s\n' "${to_remove[@]}" >"$manifest"
  chmod 0640 "$manifest" 2>/dev/null || true
  log_info "Recorded removed package manifest: $manifest"
}

# -----------------------------------------------------------------------------
# pkg_remove_from_list — Remove from a .packages file
# -----------------------------------------------------------------------------
pkg_remove_from_list() {
  local list_file="$1"
  local pkgs=()

  if [[ ! -f "$list_file" ]]; then
    log_error "Package list not found: $list_file"
    return 1
  fi

  if ! read_list_file "$list_file" pkgs; then
    log_error "Could not read package removal list: $list_file"
    return 1
  fi

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    return 0
  fi

  log_info "Removing ${#pkgs[@]} packages from $(basename "$list_file")"
  pkg_remove "${pkgs[@]}"
}

# -----------------------------------------------------------------------------
# enable_copr — Enable a COPR repository (idempotent)
# -----------------------------------------------------------------------------
enable_copr() {
  local copr_project="$1"

  if ! dnf copr --help &>/dev/null; then
    run_logged "Installing DNF COPR plugin" dnf install -y dnf-plugins-core
  fi

  if dnf copr list 2>/dev/null | grep -qi "$copr_project"; then
    log_ok "COPR $copr_project already enabled"
    return 0
  fi

  run_logged "Enabling COPR: $copr_project" dnf copr enable -y "$copr_project"
}

# -----------------------------------------------------------------------------
# repo_enable_rpm_fusion — Enable RPM Fusion free + nonfree (NEW per your request)
# -----------------------------------------------------------------------------
repo_enable_rpm_fusion() {
  if rpm -q rpmfusion-free-release &>/dev/null; then
    log_ok "RPM Fusion free already installed"
  else
    run_logged "Installing RPM Fusion free release" \
      dnf install -y \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
  fi

  if rpm -q rpmfusion-nonfree-release &>/dev/null; then
    log_ok "RPM Fusion nonfree already installed"
  else
    run_logged "Installing RPM Fusion nonfree release" \
      dnf install -y \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
  fi
}

# -----------------------------------------------------------------------------
# enable_service — Enable a systemd service
# -----------------------------------------------------------------------------
enable_service() {
  local svc="$1"
  if systemctl is-enabled "$svc" &>/dev/null; then
    log_ok "Service $svc already enabled"
  else
    run_logged "Enabling service: $svc" systemctl enable "$svc"
  fi
}

# -----------------------------------------------------------------------------
# target_user_command / run_as_target_user — Execute without shell evaluation
# -----------------------------------------------------------------------------
target_user_command() {
  if ! resolve_target_user "${TARGET_USER:-}"; then
    log_error "Could not resolve a non-root target user with a valid home directory"
    return 1
  fi

  local target_uid target_shell variable
  target_uid="$(id -u "$TARGET_USER")"
  target_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  local -a user_env=(
    "HOME=$TARGET_USER_HOME"
    "USER=$TARGET_USER"
    "LOGNAME=$TARGET_USER"
    "SHELL=$target_shell"
    "PATH=/usr/local/bin:/usr/bin:/bin"
    "LANG=${LANG:-C.UTF-8}"
  )

  if [[ -d "/run/user/$target_uid" ]]; then
    user_env+=("XDG_RUNTIME_DIR=/run/user/$target_uid")
  fi

  # Preserve proxy settings needed for downloads, but do not inherit root's
  # HOME, XDG paths, shell options, or unrelated environment variables.
  for variable in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    if [[ -n "${!variable:-}" ]]; then
      user_env+=("$variable=${!variable}")
    fi
  done

  runuser --user "$TARGET_USER" -- env -i "${user_env[@]}" "$@"
}

run_as_target_user() {
  local description="$1"
  shift
  run_logged "$description" target_user_command "$@"
}
