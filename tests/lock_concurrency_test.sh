#!/bin/bash
# =============================================================================
#  lock_concurrency_test.sh — the lock actually serialises concurrent runs
#
#  Starts WORKERS processes that race for the lock. Inside the critical section
#  each worker tries to create a holder file with noclobber (`set -C`), which is
#  an atomic O_EXCL create: if two runs are ever inside at once, the second one's
#  create fails and the overlap is recorded.
#
#  This replaced two weaker observations: a shared depth counter (left non-zero
#  if one worker died mid-section) and append ordering (which appeared to show
#  overlaps on CI runners while passing everywhere else - the append order was
#  not reliable evidence of section order).
#
#  Environment: WORKERS (default 8), ROUNDS (default 5), HOLD (default 0.05s)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

WORKERS="${WORKERS:-8}"
ROUNDS="${ROUNDS:-5}"
HOLD="${HOLD:-0.05}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for round in $(seq 1 "$ROUNDS"); do
  state="$tmp_dir/state-$round"
  events="$tmp_dir/events-$round"
  log="$tmp_dir/log-$round"
  mkdir -p "$state"
  : >"$events"
  : >"$log"

  for worker in $(seq 1 "$WORKERS"); do
    (
      export SETUP_STATE_DIR="$state"
      export SETUP_LOG="$log"
      export DRY_RUN=false VERBOSE=false FORCE=false
      export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
      # shellcheck source=lib/helpers/run_logged.sh
      source "$ROOT/lib/helpers/run_logged.sh"

      if acquire_run_lock 2>/dev/null; then
        # Atomic O_EXCL create: succeeds only if nobody else is inside.
        if ! (
          set -C
          : >"$state/holder"
        ) 2>/dev/null; then
          printf 'overlap worker=%s bashpid=%s round=%s\n' \
            "$worker" "$BASHPID" "$round" >>"$events"
        else
          printf 'enter worker=%s bashpid=%s\n' "$worker" "$BASHPID" >>"$events"
          sleep "$HOLD"
          rm -f "$state/holder"
        fi
        release_run_lock
      fi
    ) >/dev/null &
  done
  wait

  if [[ -s "$events" ]] && grep -q '^overlap' "$events"; then
    echo "--- events, round ${round} (${WORKERS} workers) ---" >&2
    cat -n "$events" >&2
    echo "--- lock dir listing ---" >&2
    ls -la "$state" >&2 || true
    fail "round ${round}: two runs held the lock at the same time"
  fi

  [[ "$(grep -c '^enter' "$events" || true)" -ge 1 ]] ||
    fail "round ${round}: nobody acquired the lock"
done

echo "lock_concurrency_test.sh: PASS (${ROUNDS} rounds x ${WORKERS} workers)"
