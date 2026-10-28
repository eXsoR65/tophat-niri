#!/bin/bash
# =============================================================================
#  preflight_stage_test.sh — Distro guard and hardware detection
#
#  require_fedora takes an explicit os-release path, so the guard is tested
#  without touching /etc/os-release. lspci is stubbed through PATH.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib" SETUP_PACKAGES="$ROOT/packages"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/preflight/detect_env.sh
source "$ROOT/lib/preflight/detect_env.sh"
# shellcheck source=lib/preflight/detect_hardware.sh
source "$ROOT/lib/preflight/detect_hardware.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

fedora_os="$tmp_dir/fedora-release"
printf 'NAME="Fedora Linux"\nID=fedora\nPRETTY_NAME="Fedora Linux 44 (Container Image)"\n' >"$fedora_os"

ubuntu_os="$tmp_dir/ubuntu-release"
printf 'NAME="Ubuntu"\nID=ubuntu\nPRETTY_NAME="Ubuntu 26.04 LTS"\n' >"$ubuntu_os"

# --- Fedora passes the guard --------------------------------------------------
require_fedora "$fedora_os" || fail "require_fedora rejected Fedora"

# --- Non-Fedora is refused with a useful message ------------------------------
if out="$(require_fedora "$ubuntu_os" 2>&1)"; then
  fail "require_fedora accepted Ubuntu"
fi
grep -q "only installs on Fedora" <<<"$out" || fail "guard message missing: $out"
grep -q "Ubuntu 26.04 LTS" <<<"$out" || fail "guard did not name the detected system: $out"

# --- A missing os-release is refused rather than assumed ----------------------
# Subshell: require_fedora calls exit, which would end the test otherwise.
if (require_fedora "$tmp_dir/does-not-exist") >/dev/null 2>&1; then
  fail "require_fedora accepted a missing os-release"
fi

# --- Intel Wi-Fi detection: present, absent, and unreliable -------------------
cat >"$stub_dir/lspci" <<'STUB'
#!/bin/bash
echo '00:14.3 Network controller: Intel Corporation Wi-Fi 6E AX211 (rev 1a)'
STUB
chmod +x "$stub_dir/lspci"

detect_intel_wifi
[[ "$HAS_INTEL_WIFI" == true ]] || fail "Intel Wi-Fi not detected with lspci output"
[[ "$INTEL_WIFI_DETECTION_RELIABLE" == true ]] || fail "detection marked unreliable with lspci"
grep -q "AX211" <<<"$INTEL_WIFI_DEVICE" || fail "device string not captured: $INTEL_WIFI_DEVICE"

cat >"$stub_dir/lspci" <<'STUB'
#!/bin/bash
echo '00:01.0 VGA compatible controller: NVIDIA Corporation GA104'
STUB

detect_intel_wifi
[[ "$HAS_INTEL_WIFI" == false ]] || fail "false-positive Intel Wi-Fi detection"
[[ "$INTEL_WIFI_DETECTION_RELIABLE" == true ]] || fail "detection marked unreliable without reason"

# --- GPU vendor classification ------------------------------------------------
detect_hardware >/dev/null 2>&1
[[ "$GPU_VENDOR" == "nvidia" ]] || fail "GPU vendor misdetected: $GPU_VENDOR"

echo "preflight_stage_test.sh: PASS"
