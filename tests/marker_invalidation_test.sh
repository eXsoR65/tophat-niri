#!/bin/bash
# =============================================================================
#  marker_invalidation_test.sh — stage markers know what they were completed with
#
#  A marker must be honoured only while the configuration that produced it is
#  unchanged: same version, same target user, same package selection.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_PACKAGES="$tmp_dir/packages"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
export TOPHAT_VERSION="2.6"
export TARGET_USER="alice"

cp -r "$ROOT/packages" "$tmp_dir/packages"
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

skip_yes() { # $1 = stage
  if stage_already_run "$1"; then return 0; fi
  return 1
}

skip_no() { # $1 = stage
  if stage_already_run "$1"; then return 1; fi
  return 0
}

# --- A marker with unchanged configuration is honoured -----------------------
stage_marker_write packaging
skip_yes packaging || fail "unchanged marker was not honoured"
[[ "${STAGE_STATUS[packaging]}" == "skipped" ]] || fail "skip status not recorded"

# --- --force always re-runs --------------------------------------------------
FORCE=true
skip_no packaging || fail "--force did not invalidate the marker"
FORCE=false

# --- A different Tophat version invalidates it ------------------------------
: >"$SETUP_LOG"
TOPHAT_VERSION="2.7"
skip_no packaging || fail "newer version did not invalidate the marker"
grep -q "ran under v2.6" "$SETUP_LOG" || fail "version invalidation not explained"
TOPHAT_VERSION="2.6"

# --- A different target user invalidates it ---------------------------------
: >"$SETUP_LOG"
TARGET_USER="bob"
skip_no packaging || fail "different target user did not invalidate the marker"
grep -q "ran for user 'alice'" "$SETUP_LOG" || fail "user invalidation not explained"
TARGET_USER="alice"

# --- A changed package selection invalidates it -----------------------------
: >"$SETUP_LOG"
printf '\nswaybg\n' >>"$SETUP_PACKAGES/desktop-support.packages"
skip_no packaging || fail "changed package list did not invalidate the marker"
grep -q "Package selection changed" "$SETUP_LOG" || fail "package invalidation not explained"

# Rewriting the marker captures the new configuration and is honoured again
stage_marker_write packaging
skip_yes packaging || fail "marker not honoured after re-recording"

# --- A marker without a recorded configuration is not trusted ---------------
rm -f "$SETUP_STATE_DIR/stage-packaging.config"
: >"$SETUP_LOG"
skip_no packaging || fail "marker without a config snapshot was trusted"
grep -q "no recorded configuration" "$SETUP_LOG" || fail "missing snapshot not explained"

# --- log_stage_complete records both the marker and the snapshot ------------
rm -f "$SETUP_STATE_DIR/stage-extras.done" "$SETUP_STATE_DIR/stage-extras.config"
STAGE_STATUS[extras]="running"
STAGE_DURATIONS[extras]="$(date +%s)"
log_stage_complete extras
[[ -f "$SETUP_STATE_DIR/stage-extras.done" ]] || fail "completion marker not written"
[[ -f "$SETUP_STATE_DIR/stage-extras.config" ]] || fail "config snapshot not written"
grep -q "^version=2.6$" "$SETUP_STATE_DIR/stage-extras.done" || fail "marker missing version"
grep -q "^user=alice$" "$SETUP_STATE_DIR/stage-extras.done" || fail "marker missing user"

echo "marker_invalidation_test.sh: PASS"
