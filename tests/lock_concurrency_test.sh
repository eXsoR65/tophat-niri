#!/bin/bash
# =============================================================================
#  lock_concurrency_test.sh — a second process cannot take a held lock
#
#  Deterministic by construction: a holder acquires the lock and stays inside
#  until told to stop, and only *then* are contenders started. Nothing races for
#  the lock at the same instant, so there is no timing heuristic to be flaky.
#
#  Earlier versions started workers simultaneously and inferred an overlap from a
#  shared counter, append order or a holder file. Those reported overlaps on CI
#  runners that no amount of local repetition (400+ rounds) reproduced, and the
#  records were not trustworthy: every worker reported the same pid, because $$ in
#  a subshell is the parent's. This asserts the property directly instead.
#
#  Environment: WORKERS (default 8, number of contenders)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

WORKERS="${WORKERS:-8}"
HOLD_TIMEOUT="${HOLD_TIMEOUT:-5}"

export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_LOG="$tmp_dir/log"
export DRY_RUN=false VERBOSE=false FORCE=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR"
: >"$SETUP_LOG"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

wait_for() { # $1 = file, $2 = what we are waiting for
  local deadline=$((SECONDS + HOLD_TIMEOUT))
  while ((SECONDS < deadline)); do
    [[ -e "$1" ]] && return 0
    sleep 0.05
  done
  fail "timed out waiting for $2"
}

released="$tmp_dir/released"
stop="$tmp_dir/stop"
holding="$tmp_dir/holding"

# --- A holder takes the lock and stays inside -------------------------------
(
  # shellcheck source=lib/helpers/run_logged.sh
  source "$ROOT/lib/helpers/run_logged.sh"
  acquire_run_lock || exit 1
  : >"$holding"
  local_deadline=$((SECONDS + HOLD_TIMEOUT))
  while [[ ! -e $stop ]] && ((SECONDS < local_deadline)); do sleep 0.05; done
  release_run_lock
  : >"$released"
) &
holder=$!

wait_for "$holding" "the holder to acquire the lock"
[[ -d "$SETUP_STATE_DIR/.lock.d" ]] || fail "holder published 'holding' without the lock directory"

# --- Every contender must be refused ----------------------------------------
attempts="$tmp_dir/attempts"
: >"$attempts"
contenders=()
for worker in $(seq 1 "$WORKERS"); do
  (
    # shellcheck source=lib/helpers/run_logged.sh
    source "$ROOT/lib/helpers/run_logged.sh"
    if acquire_run_lock 2>/dev/null; then
      printf 'worker %s acquired the held lock\n' "$worker" >>"$attempts"
      release_run_lock
    fi
  ) >/dev/null &
  contenders+=($!)
done
for pid in "${contenders[@]}"; do
  wait "$pid" || fail "a contender exited non-zero"
done

[[ ! -s "$attempts" ]] || {
  cat "$attempts" >&2
  fail "a contender acquired the lock while the holder was inside"
}

grep -q 'Another Tophat run is in progress' "$SETUP_LOG" || fail "refusal not explained in the log"

# --- Releasing frees it ------------------------------------------------------
: >"$stop"
wait "$holder" || fail "holder exited non-zero"
wait_for "$released" "the holder to release"
[[ ! -e "$SETUP_STATE_DIR/.lock.d" ]] || fail "lock directory left behind after release"

(
  # shellcheck source=lib/helpers/run_logged.sh
  source "$ROOT/lib/helpers/run_logged.sh"
  acquire_run_lock || exit 1
  release_run_lock
) || fail "lock was not acquirable after release"

echo "lock_concurrency_test.sh: PASS (${WORKERS} contenders refused, then acquired after release)"
