#!/bin/bash
# =============================================================================
#  packaging_stage_test.sh — Packaging stage wiring
#
#  dnf and rpm are stubbed. Asserts the conditional Intel Wi-Fi firmware, the
#  DMS install path, the optional-applications guidance, and the stage marker.
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

DNF_CALLS="$tmp_dir/dnf-calls"
export DNF_CALLS
: >"$DNF_CALLS"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"

cat >"$stub_dir/dnf" <<'STUB'
#!/bin/bash
echo "$*" >>"$DNF_CALLS"
exit 0
STUB

cat >"$stub_dir/rpm" <<'STUB'
#!/bin/bash
if [[ "$1" == "-E" ]]; then
  echo "44"
  exit 0
fi
exit 1
STUB

chmod +x "$stub_dir/dnf" "$stub_dir/rpm"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"
# shellcheck source=lib/packaging/all.sh
source "$ROOT/lib/packaging/all.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Intel Wi-Fi present: firmware packages are installed --------------------
export INTEL_WIFI_DETECTION_RELIABLE=true
export HAS_INTEL_WIFI=true
FORCE=true
: >"$DNF_CALLS"
run_packaging_stage >/dev/null

grep -q "iwlwifi-mvm-firmware" "$DNF_CALLS" || fail "Intel Wi-Fi firmware not installed"
grep -q "iwlwifi-dvm-firmware" "$DNF_CALLS" || fail "dvm firmware missing from install set"
grep -q "install -y dms" "$DNF_CALLS" || fail "DMS package not installed"
grep -q "desktop-support" "$SETUP_LOG" || fail "desktop support list not processed"

# --- Intel Wi-Fi absent: firmware packages are skipped ----------------------
export HAS_INTEL_WIFI=false
: >"$DNF_CALLS"
run_packaging_stage >/dev/null
if grep -q "iwlwifi" "$DNF_CALLS"; then
  fail "Intel Wi-Fi firmware installed without Intel Wi-Fi: $(cat "$DNF_CALLS")"
fi
grep -q "Skipping Intel Wi-Fi firmware" "$SETUP_LOG" || fail "skip not logged"

# --- Missing applications list is guidance, not a warning -------------------
if grep -q "applications.packages not found" "$SETUP_LOG"; then
  fail "applications guidance still uses warn wording"
fi
grep -q "No applications.packages" "$SETUP_LOG" || fail "applications guidance not logged"

# --- The stage marker short-circuits a re-run -------------------------------
stage_marker_write packaging
FORCE=false
: >"$DNF_CALLS"
run_packaging_stage >/dev/null
[[ ! -s "$DNF_CALLS" ]] || fail "marked stage still called dnf: $(cat "$DNF_CALLS")"

echo "packaging_stage_test.sh: PASS"
