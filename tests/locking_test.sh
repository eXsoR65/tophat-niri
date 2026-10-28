#!/bin/bash
# =============================================================================
#  locking_test.sh — one installer at a time
#
#  A single mechanism, an atomic `mkdir` lock directory with a pid file. It is
#  never reclaimed automatically: reclaiming races with acquiring, so a stale
#  directory is reported with the command to remove it.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false FORCE=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- A free lock is taken -----------------------------------------------------
acquire_run_lock || fail "could not acquire a free lock"
[[ -d "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock directory not created"
[[ "$(<"$SETUP_STATE_DIR/.lock.d/pid")" == "$$" ]] || fail "lock does not hold our pid"

# --- A second run is refused while the first is alive ------------------------
: >"$SETUP_LOG"
if (acquire_run_lock) >/dev/null 2>&1; then
  fail "second concurrent run acquired the lock"
fi
grep -q 'Another Tophat run is in progress' "$SETUP_LOG" || fail "in-progress message not logged"

# --- Releasing lets the next run in ------------------------------------------
release_run_lock
[[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock left behind after release"
acquire_run_lock || fail "could not re-acquire after release"
release_run_lock

# --- A holder that exits without releasing does not wedge the machine --------
# The directory is removed by the EXIT trap.
(acquire_run_lock) || fail "subshell could not acquire the lock"
acquire_run_lock || fail "lock leaked after the holder exited"
release_run_lock

# --- A stale lock is reported, never reclaimed automatically ----------------
mkdir -p "$SETUP_STATE_DIR/.lock.d"
printf '%s\n' 999999 >"$SETUP_STATE_DIR/.lock.d/pid"
: >"$SETUP_LOG"
if acquire_run_lock 2>/dev/null; then
  fail "stale lock was reclaimed automatically"
fi
grep -q 'remove it and retry' "$SETUP_LOG" || fail "no manual-cleanup guidance logged"
[[ -d "$SETUP_STATE_DIR/.lock.d" ]] || fail "stale lock directory was removed"

# --- ...including when the pid was never written ---------------------------
rm -rf "$SETUP_STATE_DIR/.lock.d"
mkdir -p "$SETUP_STATE_DIR/.lock.d"
: >"$SETUP_LOG"
if acquire_run_lock 2>/dev/null; then
  fail "a lock directory without a pid was reclaimed automatically"
fi
grep -q 'remove it and retry' "$SETUP_LOG" || fail "no manual-cleanup guidance logged"

rm -rf "$SETUP_STATE_DIR/.lock.d"
[[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock artifacts left behind"

echo "locking_test.sh: PASS"
