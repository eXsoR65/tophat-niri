#!/bin/bash
# =============================================================================
#  lock_concurrency_test.sh — the lock actually serialises concurrent runs
#
#  Starts WORKERS processes that race for the lock. Inside the critical section
#  each one increments a counter and checks it, so a second concurrent holder is
#  detected exactly rather than inferred from timestamps (timestamps tie at
#  millisecond granularity and made this test flaky on loaded runners).
#
#  The counter is only read and written while holding the lock, so it is itself
#  serialised: if two runs ever hold the lock at once, the second sees depth 2.
#
#  Environment: WORKERS (default 8), ROUNDS (default 5)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

WORKERS="${WORKERS:-8}"
ROUNDS="${ROUNDS:-5}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for round in $(seq 1 "$ROUNDS"); do
  state="$tmp_dir/state-$round"
  counter="$tmp_dir/depth-$round"
  violations="$tmp_dir/violations-$round"
  log="$tmp_dir/log-$round"
  mkdir -p "$state"
  printf '0' >"$counter"
  : >"$violations"
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
        depth="$(<"$counter")"
        depth=$((depth + 1))
        printf '%s' "$depth" >"$counter"
        if ((depth > 1)); then
          printf 'worker %s entered while depth was %s\n' "$worker" "$depth" >>"$violations"
        fi
        sleep 0.05
        depth="$(<"$counter")"
        printf '%s' "$((depth - 1))" >"$counter"
        release_run_lock
      fi
    ) >/dev/null &
  done
  wait

  if [[ -s "$violations" ]]; then
    cat "$violations" >&2
    fail "round ${round}: two runs held the lock at the same time"
  fi
  [[ "$(<"$counter")" == 0 ]] || fail "round ${round}: counter did not return to 0"
done

echo "lock_concurrency_test.sh: PASS (${ROUNDS} rounds x ${WORKERS} workers)"
