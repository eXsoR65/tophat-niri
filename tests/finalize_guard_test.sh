#!/bin/bash
# =============================================================================
#  finalize_guard_test.sh — D2.3: finalize refuses on incomplete installs
#
#  dnf is stubbed through PATH so the cleanup steps are harmless.
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
export TOPHAT_VERSION="test"
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
printf '#!/bin/bash\nexit 0\n' >"$stub_dir/dnf"
chmod +x "$stub_dir/dnf"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/finalize/all.sh
source "$ROOT/lib/finalize/all.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

mark_done() { # $1 = stage name
  date '+%Y-%m-%d %H:%M:%S' >"$SETUP_STATE_DIR/stage-$1.done"
}

# --- No markers: refuse and list every required stage -------------------------
if out="$(run_finalize_stage 2>&1)"; then
  fail "finalize ran without any stage markers"
fi
grep -q "incomplete stages: preflight repos packaging config services" <<<"$out" ||
  fail "refusal did not list all stages: $out"

# --- Partial markers: refuse and list only the missing ones --------------------
mark_done preflight
mark_done repos
mark_done packaging
if out="$(run_finalize_stage 2>&1)"; then
  fail "finalize ran with missing markers"
fi
grep -q "incomplete stages: config services" <<<"$out" ||
  fail "refusal did not list missing stages: $out"
grep -q -- "--select config,services" <<<"$out" ||
  fail "refusal did not suggest --select: $out"

# --- All markers present: finalize completes and writes .completed -------------
mark_done config
mark_done services
run_finalize_stage >/dev/null
[[ -f "$SETUP_STATE_DIR/.completed" ]] || fail ".completed not written after full run"
grep -q "^version=test$" "$SETUP_STATE_DIR/.completed" ||
  fail ".completed missing version entry"

# --- --force overrides the guard ----------------------------------------------
export SETUP_STATE_DIR="$tmp_dir/forced-state"
mkdir -p "$SETUP_STATE_DIR"
FORCE=true run_finalize_stage >/dev/null
[[ -f "$SETUP_STATE_DIR/.completed" ]] || fail ".completed not written with --force"

# --- Dry run does not trip the guard -------------------------------------------
export SETUP_STATE_DIR="$tmp_dir/dry-state"
mkdir -p "$SETUP_STATE_DIR"
if ! out="$(DRY_RUN=true run_finalize_stage 2>&1)"; then
  fail "dry-run finalize failed: $out"
fi
[[ ! -e "$SETUP_STATE_DIR/.completed" ]] || fail ".completed written during dry run"

echo "finalize_guard_test.sh: PASS"
