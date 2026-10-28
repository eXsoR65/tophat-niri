#!/bin/bash
# =============================================================================
#  locking_test.sh — one installer at a time
#
#  The lock is a directory with a pid file: held while a live run exists, broken
#  when the recorded pid is gone, so a killed run cannot block the machine.
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
if (acquire_run_lock) >/dev/null 2>&1; then
  fail "second concurrent run acquired the lock"
fi

# --- Releasing lets the next run in ------------------------------------------
release_run_lock
[[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock not removed on release"
acquire_run_lock || fail "could not re-acquire after release"
release_run_lock

# --- A lock whose owner is about to publish its pid is not stolen -----------
# The owner creates the directory first and writes the pid a moment later; a
# second run must wait for the pid rather than assume the owner is dead.
mkdir -p "$SETUP_STATE_DIR/.lock.d"
owner_pid=$$
(sleep 0.5 && printf '%s\n' "$owner_pid" >"$SETUP_STATE_DIR/.lock.d/pid") &
publisher=$!
if (acquire_run_lock) >/dev/null 2>&1; then
  fail 'stole a lock whose pid was published late'
fi
wait "$publisher" 2>/dev/null || true
rm -rf "$SETUP_STATE_DIR/.lock.d"

# --- A lock directory with no pid at all is reclaimed after a grace period ---
mkdir -p "$SETUP_STATE_DIR/.lock.d"
if ! (acquire_run_lock); then
  fail 'a lock with no pid was never reclaimed'
fi
rm -rf "$SETUP_STATE_DIR/.lock.d"

# --- A stale lock (dead pid) is broken, not obeyed ---------------------------
mkdir -p "$SETUP_STATE_DIR/.lock.d"
printf '%s\n' 999999 >"$SETUP_STATE_DIR/.lock.d/pid"
: >"$SETUP_LOG"
acquire_run_lock || fail "stale lock blocked a new run"
grep -q "Breaking stale Tophat lock" "$SETUP_LOG" || fail "stale lock break not logged"
[[ "$(<"$SETUP_STATE_DIR/.lock.d/pid")" == "$$" ]] || fail "stale lock not replaced"
release_run_lock

# --- A lock with no pid file at all is also treated as stale -----------------
mkdir -p "$SETUP_STATE_DIR/.lock.d"
acquire_run_lock || fail "lock without a pid file blocked a new run"
release_run_lock

[[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock left behind after release"

echo "locking_test.sh: PASS"
