# =============================================================================
#  flatpak.sh — Optional user-scoped Flathub applications
# =============================================================================

FLATPAK_LIST="$SETUP_PACKAGES/flatpaks.packages"
FLATHUB_REPO_FILE="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_REPO_URL="https://dl.flathub.org/repo/"

if [[ ! -e "$FLATPAK_LIST" ]]; then
  log_info "flatpaks.packages not found; skipping Flatpak support"
elif [[ ! -f "$FLATPAK_LIST" ]]; then
  log_error "Flatpak selection is not a regular file: $FLATPAK_LIST"
  exit 1
else
  flatpak_apps=()
  if ! read_list_file "$FLATPAK_LIST" flatpak_apps; then
    log_error "Could not read Flatpak selections"
    exit 1
  fi

  for app_id in "${flatpak_apps[@]}"; do
    if [[ ! "$app_id" =~ ^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+){2,}$ ]]; then
      log_error "Invalid Flatpak application ID in $(basename "$FLATPAK_LIST"): $app_id"
      exit 1
    fi
  done

  if ! resolve_target_user "${TARGET_USER:-}"; then
    log_error "Could not resolve the target user for Flatpak installation"
    exit 1
  fi

  log_info "Enabling user-scoped Flatpak support for $TARGET_USER..."
  pkg_install "flatpak"

  flathub_url=""
  if [[ "$DRY_RUN" != true ]]; then
    while IFS=$'\t' read -r remote_name remote_url; do
      if [[ "$remote_name" == "flathub" ]]; then
        flathub_url="$remote_url"
        break
      fi
    done < <(target_user_command flatpak remote-list --user --columns=name,url 2>>"$SETUP_LOG")
  fi

  if [[ -z "$flathub_url" ]]; then
    run_as_target_user "Adding the Flathub user remote" \
      flatpak remote-add --user --if-not-exists flathub "$FLATHUB_REPO_FILE"
  elif [[ "${flathub_url%/}/" == "$FLATHUB_REPO_URL" ]]; then
    log_ok "Flathub user remote already configured for $TARGET_USER"
  else
    log_error "Existing flathub remote has an unexpected URL: $flathub_url"
    log_error "Refusing to replace it automatically; expected $FLATHUB_REPO_URL"
    exit 1
  fi

  if [[ ${#flatpak_apps[@]} -eq 0 ]]; then
    log_info "No Flatpak application IDs selected"
  fi

  for app_id in "${flatpak_apps[@]}"; do
    if [[ "$DRY_RUN" != true ]] && target_user_command flatpak info --user "$app_id" &>/dev/null; then
      log_ok "Flatpak already installed: $app_id"
    else
      run_as_target_user "Installing Flatpak: $app_id" \
        flatpak install --user --noninteractive -y flathub "$app_id"
    fi
  done
fi
