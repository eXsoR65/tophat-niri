#!/bin/bash
# =============================================================================
#  lock_concurrency_test.sh — the lock actually serialises concurrent runs
#
#  Starts WORKERS processes that race for the lock. Each records when it enters
#  and leaves the critical section; the merged timeline must never contain two
#  holders at once. This is the test that sequential assertions could not write:
#  the previous bugs (pid-publish window, reclaim stealing a live lock, unlinking
#  the lock file) only appear when processes interleave.
#
#  Environment:
#    WORKERS (default 8), ROUNDS (default 5), TOPHAT_LOCK_BACKEND (auto|flock|directory)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

WORKERS="${WORKERS:-8}"
ROUNDS="${ROUNDS:-5}"
backend="${TOPHAT_LOCK_BACKEND:-auto}"

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
      export TOPHAT_LOCK_BACKEND="$backend"
      export DRY_RUN=false VERBOSE=false FORCE=false
      export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
      # shellcheck source=lib/helpers/run_logged.sh
      source "$ROOT/lib/helpers/run_logged.sh"
      if acquire_run_lock 2>/dev/null; then
        printf 'enter %s %s\n' "$worker" "$(date +%s%3N)" >>"$events"
        sleep 0.05
        printf 'exit %s %s\n' "$worker" "$(date +%s%3N)" >>"$events"
        release_run_lock
      fi
    ) >/dev/null &
  done
  wait

  # Replay the timeline in time order: depth must never exceed 1.
  if ! sort -k3 -n "$events" | awk '
    $1 == "enter" { depth++; if (depth > 1) { print "overlap at: " $0 > "/dev/stderr"; bad = 1 } }
    $1 == "exit" { depth-- }
    END {
      if (depth != 0) { print "unbalanced timeline, depth " depth > "/dev/stderr"; bad = 1 }
      exit bad
    }
  '; then
    fail "round ${round}: two runs held the lock at the same time"
  fi

  holders="$(grep -c '^enter' "$events" || true)"
  [[ "$holders" -ge 1 ]] || fail "round ${round}: nobody acquired the lock"
done

# shellcheck disable=SC2031 # backend is only read inside the workers
echo "lock_concurrency_test.sh: PASS (${backend}, ${ROUNDS} rounds x ${WORKERS} workers)"
