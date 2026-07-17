# =============================================================================
#  hardware_firmware.sh — Hardware-specific firmware packages
# =============================================================================

# Support running `--select packaging` without running preflight in the same
# invocation. If hardware detection was not already done, source the detection
# module and run only the Intel Wi-Fi check.
if [[ "${HAS_INTEL_WIFI:-false}" != true ]]; then
  if [[ -f "$SETUP_LIB/preflight/detect_hardware.sh" ]]; then
    source "$SETUP_LIB/preflight/detect_hardware.sh"
    detect_intel_wifi
  else
    log_warn "Hardware detection module not found; skipping hardware-specific firmware"
  fi
fi

if [[ "${HAS_INTEL_WIFI:-false}" == true ]]; then
  log_info "Installing Intel Wi-Fi firmware packages..."
  pkg_install_from_list "$SETUP_PACKAGES/intel-wifi.packages"
else
  log_info "Skipping Intel Wi-Fi firmware packages — no Intel Wi-Fi detected"
fi
