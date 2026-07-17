# =============================================================================
#  detect_hardware.sh — Detect GPU, form factor, and peripherals
# =============================================================================

export GPU_VENDOR="none"
export HAS_BATTERY=false
export FORM_FACTOR="desktop"
export HAS_INTEL_WIFI=false
export INTEL_WIFI_DEVICE=""

detect_intel_wifi() {
  HAS_INTEL_WIFI=false
  INTEL_WIFI_DEVICE=""

  if ! cmd_present lspci; then
    log_warn "lspci not found; Intel Wi-Fi detection skipped until pciutils is installed"
    export HAS_INTEL_WIFI INTEL_WIFI_DEVICE
    return 0
  fi

  INTEL_WIFI_DEVICE="$(
    lspci 2>/dev/null |
      grep -Ei 'network controller|wireless|wi-fi|wifi' |
      grep -Ei 'intel' |
      head -1 || true
  )"

  if [[ -n "$INTEL_WIFI_DEVICE" ]]; then
    HAS_INTEL_WIFI=true
    log_ok "Intel Wi-Fi detected: $INTEL_WIFI_DEVICE"
  else
    log_info "No Intel Wi-Fi detected"
  fi

  export HAS_INTEL_WIFI INTEL_WIFI_DEVICE
}

detect_hardware() {
  log_info "Detecting hardware..."

  # --- GPU detection via PCI display controller class (0300) ---
  local gpu_line=""
  local gpu_detection_available=false
  if cmd_present lspci; then
    gpu_detection_available=true
    gpu_line="$(lspci -d ::0300 2>/dev/null | head -1 || true)"
  else
    log_warn "lspci not found; GPU detection skipped until pciutils is installed"
  fi

  if echo "$gpu_line" | grep -qi "nvidia"; then
    GPU_VENDOR="nvidia"
  elif echo "$gpu_line" | grep -qi "amd\|advanced micro devices"; then
    GPU_VENDOR="amd"
  elif echo "$gpu_line" | grep -qi "intel"; then
    GPU_VENDOR="intel"
  elif [[ -n "$gpu_line" ]]; then
    GPU_VENDOR="unknown"
    log_warn "Unrecognised GPU: $gpu_line"
  else
    GPU_VENDOR="none"
    if [[ "$gpu_detection_available" == true ]]; then
      log_warn "No PCI GPU detected"
    fi
  fi

  log_info "GPU vendor: $GPU_VENDOR"

  # --- Intel Wi-Fi detection for conditional firmware install ---
  detect_intel_wifi

  # --- Laptop / desktop detection via battery presence ---
  if ls /sys/class/power_supply/BAT* &>/dev/null 2>&1; then
    HAS_BATTERY=true
    FORM_FACTOR="laptop"
    log_info "Battery detected — form factor: laptop"
  else
    HAS_BATTERY=false
    FORM_FACTOR="desktop"
    log_info "No battery — form factor: desktop"
  fi

  # Additional hardware info logged for reference
  local cpu_model="unknown"
  if [[ -r /proc/cpuinfo ]]; then
    cpu_model="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs || true)"
    [[ -n "$cpu_model" ]] || cpu_model="unknown"
  fi
  log_info "CPU: $cpu_model"

  local total_ram="unknown"
  if cmd_present free; then
    total_ram="$(free -h | awk '/^Mem:/ {print $2}' || true)"
    [[ -n "$total_ram" ]] || total_ram="unknown"
  fi
  log_info "Total RAM: $total_ram"

  if cmd_present lsblk; then
    log_info "Block devices:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | while read -r line; do
      log_info "  $line"
    done
  else
    log_warn "lsblk not found; block device summary skipped"
  fi

  log_ok "Hardware detection complete"
}
