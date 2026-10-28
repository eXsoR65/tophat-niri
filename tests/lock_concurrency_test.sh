#!/bin/bash
# =============================================================================
#  lock_concurrency_test.sh — the lock actually serialises concurrent runs
#
#  Starts WORKERS processes that race for the lock. Inside the critical section
#  each one appends "start" then "end" to a shared events file.
#
#  Because those appends happen only while holding the lock, the file order *is*
#  the order of critical sections. A working lock therefore leaves exactly
#  start,end,start,end... - no clocks, no shared counter, nothing that depends on
#  scheduling. Two runs inside at once (or a section that never closes) shows up
#  as two consecutive starts or a missing end.
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
        printf 'start %s\n' "$worker" >>"$events"
        sleep 0.05
        printf 'end %s\n' "$worker" >>"$events"
        release_run_lock
      fi
    ) >/dev/null &
  done
  wait

  holders="$(grep -c '^start' "$events" || true)"
  [[ "$holders" -ge 1 ]] || fail "round ${round}: nobody acquired the lock"

  if ! awk '
    $1 == "start" {
      if (inside) { printf "overlap: second start while still inside (%s)\n", $0; bad = 1 }
      inside = 1
    }
    $1 == "end" {
      if (!inside) { printf "unbalanced end without start (%s)\n", $0; bad = 1 }
      inside = 0
    }
    END {
      if (inside) { print "unbalanced: critical section never closed"; bad = 1 }
      exit bad
    }
  ' "$events"; then
    fail "round ${round}: concurrent holders or a section that never closed"
  fi
done

echo "lock_concurrency_test.sh: PASS (${ROUNDS} rounds x ${WORKERS} workers)"
