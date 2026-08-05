#!/bin/bash
# =============================================================================
#  config_stage_test.sh — Config stage behavior (lib/config/user_services.sh)
#
#  Guards the decision that the installer never runs 'dms setup' (it requires
#  a graphical session and only ever hung or failed from a root context):
#  a stub dms acts as a tripwire, and the post-login guidance must be logged.
#
#  getent is stubbed through PATH so TARGET_USER_HOME points at a temp
#  directory instead of the real $HOME.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib" SETUP_PACKAGES="$ROOT/packages"
export TARGET_USER
TARGET_USER="$(id -un)"
export SRC_FILE="$ROOT/lib/config/user_services.sh"
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
export STUB_HOME="$tmp_dir/fake-home"
export DMS_TRIPWIRE="$tmp_dir/dms-was-called"
mkdir -p "$STUB_HOME"

# getent: report a fake home inside the temp dir (avoid touching real $HOME)
cat >"$stub_dir/getent" <<'STUB'
#!/bin/bash
if [[ "$1" == "passwd" ]]; then
  echo "$2:x:$(id -u "$2"):$(id -g "$2")::${STUB_HOME:-/tmp}:/bin/bash"
  exit 0
fi
exit 2
STUB

# dms: tripwire — the config stage must never invoke dms
cat >"$stub_dir/dms" <<'STUB'
#!/bin/bash
echo "called with: $*" >"$DMS_TRIPWIRE"
exit 0
STUB

chmod +x "$stub_dir/getent" "$stub_dir/dms"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Config stage completes and never calls dms -------------------------------
source "$SRC_FILE"

[[ ! -e "$DMS_TRIPWIRE" ]] ||
  fail "config stage invoked dms: $(cat "$DMS_TRIPWIRE")"

grep -q "Skipping 'dms setup'" "$SETUP_LOG" ||
  fail "post-login 'dms setup' guidance not logged"

# --- Fake home was configured, real HOME untouched ----------------------------
[[ -d "$STUB_HOME/.config/niri" ]] || fail "config dirs not created in target home"
[[ -d "$STUB_HOME/.config/environment.d" ]] ||
  fail "environment.d not created in target home"
[[ ! -e "$HOME/.config/niri" ]] || fail "test polluted real HOME"

# --- Missing dms.service warns instead of failing -----------------------------
grep -q "Could not find dms.service" "$SETUP_LOG" ||
  fail "missing dms.service did not produce a warning"

echo "config_stage_test.sh: PASS"
