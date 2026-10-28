#!/bin/bash
# =============================================================================
#  locking_test.sh — one installer at a time
#
#  Runs the same scenarios against both lock backends:
#   - flock: kernel-managed, released when the holder exits, so there is no
#     stale lock to reclaim and no reclaim race.
#   - directory: the fallback when flock is absent. Deliberately never reclaimed
#     automatically, because reclaiming races with acquisition; a stale
#     directory is reported for a human instead.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export DRY_RUN=false VERBOSE=false FORCE=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"

fail() {
  echo "FAIL: ${1}" >&2
  exit 1
}

run_backend() { # $1 = flock | directory
  local backend="$1"
  local state="$tmp_dir/state-${backend}"

  (
    export SETUP_STATE_DIR="$state"
    export SETUP_LOG="$tmp_dir/log-${backend}"
    export TOPHAT_LOCK_BACKEND="$backend"
    mkdir -p "$SETUP_STATE_DIR"
    : >"$SETUP_LOG"

    # --- A free lock is taken -------------------------------------------------
    acquire_run_lock || fail "${backend}: could not acquire a free lock"
    if [[ "$backend" == flock ]]; then
      [[ -f "$SETUP_STATE_DIR/.lock" ]] || fail "${backend}: lock file not created"
    else
      [[ -d "$SETUP_STATE_DIR/.lock.d" ]] || fail "${backend}: lock directory not created"
      [[ "$(<"$SETUP_STATE_DIR/.lock.d/pid")" == "$$" ]] || fail "${backend}: pid not recorded"
    fi

    # --- A second run is refused while the first is alive --------------------
    if (acquire_run_lock) >/dev/null 2>&1; then
      fail "${backend}: second concurrent run acquired the lock"
    fi

    # --- Releasing lets the next run in --------------------------------------
    release_run_lock
    if [[ "$backend" == flock ]]; then
      # The lock file must stay: unlinking it would let a second run lock the old
      # inode while a third locks a fresh .lock.
      [[ -f "$SETUP_STATE_DIR/.lock" ]] ||
        fail "${backend}: lock file was unlinked after release"
    else
      [[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "${backend}: lock directory left behind"
    fi
    acquire_run_lock || fail "${backend}: could not re-acquire after release"
    release_run_lock

    # --- A holder that dies without releasing does not wedge the machine -----
    (acquire_run_lock) || fail "${backend}: subshell could not acquire"
    if ! acquire_run_lock 2>/dev/null; then
      fail "${backend}: lock leaked after the holder exited"
    fi
    release_run_lock

    # --- Leftovers: ignored by flock, reported by the directory backend ------
    mkdir -p "$SETUP_STATE_DIR/.lock.d"
    printf '%s\n' 999999 >"$SETUP_STATE_DIR/.lock.d/pid"
    if [[ "$backend" == flock ]]; then
      acquire_run_lock || fail "${backend}: a leftover directory blocked the lock"
      release_run_lock
    else
      if acquire_run_lock 2>/dev/null; then
        fail "${backend}: stale lock directory was reclaimed automatically"
      fi
      grep -q 'stale lock directory' "$SETUP_LOG" ||
        fail "${backend}: no manual-cleanup guidance logged"
    fi

    rm -rf "$SETUP_STATE_DIR/.lock.d"
    [[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "${backend}: lock directory left behind"
  )
}

if command -v flock >/dev/null 2>&1; then
  run_backend flock || exit 1
else
  echo 'locking_test.sh: flock unavailable, skipping the flock backend'
fi
run_backend directory || exit 1

echo "locking_test.sh: PASS"
