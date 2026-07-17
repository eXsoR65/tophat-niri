# =============================================================================
#  homebrew.sh — Optional Homebrew for Linux and selected formulae
# =============================================================================

HOMEBREW_LIST="$SETUP_PACKAGES/homebrew.packages"
HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

configure_homebrew_environment() {
  local env_dir="$TARGET_USER_HOME/.config/environment.d"
  local env_file="$env_dir/90-homebrew.conf"
  local profile_file="$TARGET_USER_HOME/.bash_profile"
  local shell_path target_group
  shell_path="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  target_group="$(id -gn "$TARGET_USER")"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would write $env_file"
    if [[ "$(basename "$shell_path")" == "bash" ]]; then
      log_info "[DRY-RUN] Would add a managed Homebrew block to $profile_file"
    fi
    return 0
  fi

  if [[ -L "$env_file" ]]; then
    log_error "Refusing to replace symlinked Homebrew environment file: $env_file"
    return 1
  fi

  local env_tmp
  env_tmp="$(mktemp)"
  cat >"$env_tmp" <<'EOF'
# Managed by Tophat
HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar
HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew
PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}
EOF

  run_logged "Creating the target user's environment.d directory" \
    install -d -m 0755 -o "$TARGET_USER" -g "$target_group" "$env_dir"
  run_logged "Installing the Homebrew graphical-session environment" \
    install -m 0644 -o "$TARGET_USER" -g "$target_group" "$env_tmp" "$env_file"
  rm -f -- "$env_tmp"

  if [[ "$(basename "$shell_path")" == "bash" ]]; then
    if [[ -L "$profile_file" ]]; then
      log_warn "Skipping Homebrew Bash profile update because $profile_file is a symlink"
    elif [[ -e "$profile_file" && ! -f "$profile_file" ]]; then
      log_error "Refusing to modify non-regular Bash profile: $profile_file"
      return 1
    elif [[ -f "$profile_file" ]] && grep -Fq '# >>> tophat homebrew >>>' "$profile_file"; then
      log_ok "Homebrew Bash profile block already present"
    else
      if [[ ! -e "$profile_file" ]]; then
        install -m 0644 -o "$TARGET_USER" -g "$target_group" /dev/null "$profile_file"
      fi
      cat >>"$profile_file" <<'EOF'

# >>> tophat homebrew >>>
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# <<< tophat homebrew <<<
EOF
      chown "$TARGET_USER:$target_group" "$profile_file"
      log_ok "Added managed Homebrew block to $profile_file"
    fi
  else
    log_warn "Shell $shell_path was not modified; Homebrew is available in graphical sessions"
    log_warn "For shell sessions, add: eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""
  fi
}

find_working_brew() {
  local candidate="$HOMEBREW_PREFIX/bin/brew"
  if [[ -x "$candidate" ]] && target_user_command "$candidate" --version &>/dev/null; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

install_homebrew_for_target() {
  local primary_group
  primary_group="$(id -gn "$TARGET_USER")"

  if [[ -L /home/linuxbrew ]]; then
    log_error "Refusing to use symlinked Linuxbrew parent: /home/linuxbrew"
    return 1
  elif [[ ! -e /home/linuxbrew ]]; then
    run_logged "Creating the Linuxbrew parent directory" \
      install -d -m 0755 -o "$TARGET_USER" -g "$primary_group" /home/linuxbrew
  elif [[ ! -d /home/linuxbrew ]]; then
    log_error "/home/linuxbrew exists but is not a directory"
    return 1
  fi

  if [[ -L "$HOMEBREW_PREFIX" ]]; then
    log_error "Refusing to use symlinked Linuxbrew prefix: $HOMEBREW_PREFIX"
    return 1
  elif [[ ! -e "$HOMEBREW_PREFIX" ]]; then
    run_logged "Preparing the standard Linuxbrew prefix" \
      install -d -m 0755 -o "$TARGET_USER" -g "$primary_group" "$HOMEBREW_PREFIX"
  elif [[ ! -d "$HOMEBREW_PREFIX" ]]; then
    log_error "$HOMEBREW_PREFIX exists but is not a directory"
    return 1
  elif ! target_user_command test -w "$HOMEBREW_PREFIX"; then
    log_error "Existing Linuxbrew prefix is not writable by $TARGET_USER: $HOMEBREW_PREFIX"
    log_error "Refusing to change ownership of an existing prefix"
    return 1
  fi

  local installer_tmp
  installer_tmp="$(mktemp /tmp/tophat-homebrew.XXXXXX)"
  chmod 0644 "$installer_tmp"
  trap 'rm -f -- "${installer_tmp:-}"' EXIT

  run_logged "Downloading the official Homebrew installer from $HOMEBREW_INSTALL_URL" \
    curl --fail --show-error --location --proto '=https' --tlsv1.2 \
    --output "$installer_tmp" "$HOMEBREW_INSTALL_URL"

  run_as_target_user "Installing Homebrew for Linux as $TARGET_USER" \
    env NONINTERACTIVE=1 CI=1 /bin/bash "$installer_tmp"

  rm -f -- "$installer_tmp"
  trap - EXIT
}

if [[ ! -e "$HOMEBREW_LIST" ]]; then
  log_info "homebrew.packages not found; skipping Homebrew"
elif [[ ! -f "$HOMEBREW_LIST" ]]; then
  log_error "Homebrew selection is not a regular file: $HOMEBREW_LIST"
  exit 1
else
  brew_formulae=()
  if ! read_list_file "$HOMEBREW_LIST" brew_formulae; then
    log_error "Could not read Homebrew formula selections"
    exit 1
  fi

  for formula in "${brew_formulae[@]}"; do
    if [[ ! "$formula" =~ ^[A-Za-z0-9][A-Za-z0-9@+._/-]*$ || "$formula" == *".."* ]]; then
      log_error "Invalid Homebrew formula in $(basename "$HOMEBREW_LIST"): $formula"
      exit 1
    fi
  done

  if ! resolve_target_user "${TARGET_USER:-}"; then
    log_error "Could not resolve the target user for Homebrew installation"
    exit 1
  fi

  case "$(uname -m)" in
    x86_64 | aarch64 | arm64) ;;
    *)
      log_error "Homebrew is not enabled by Tophat on architecture: $(uname -m)"
      exit 1
      ;;
  esac

  log_info "Installing Homebrew prerequisites..."
  pkg_install procps-ng curl file git gcc gcc-c++ make glibc-devel

  brew_bin=""
  if brew_bin="$(find_working_brew)"; then
    log_ok "Using existing Homebrew installation: $brew_bin"
  elif [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would download and run the official Homebrew installer as $TARGET_USER"
    brew_bin="$HOMEBREW_PREFIX/bin/brew"
  else
    install_homebrew_for_target
    if ! brew_bin="$(find_working_brew)"; then
      log_error "Homebrew installer completed but brew is not usable by $TARGET_USER"
      exit 1
    fi
    log_ok "Homebrew installed: $brew_bin"
  fi

  configure_homebrew_environment

  if [[ ${#brew_formulae[@]} -eq 0 ]]; then
    log_info "No Homebrew formulae selected"
  fi

  for formula in "${brew_formulae[@]}"; do
    if [[ "$DRY_RUN" != true ]] && target_user_command "$brew_bin" list --formula --versions "$formula" &>/dev/null; then
      log_ok "Homebrew formula already installed: $formula"
    else
      run_as_target_user "Installing Homebrew formula: $formula" \
        env HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install --formula "$formula"
    fi
  done
fi
