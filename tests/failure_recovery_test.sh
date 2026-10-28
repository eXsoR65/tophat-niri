#!/bin/bash
# =============================================================================
#  failure_recovery_test.sh — a failed or interrupted stage is never marked done
#
#  The safety property that makes reruns trustworthy: markers are written only
#  after a stage's work succeeds, so an interrupted install resumes instead of
#  pretending to be complete.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_PACKAGES="$tmp_dir/packages"
export DRY_RUN=false VERBOSE=false FORCE=false
export TOPHAT_VERSION="2.7" TARGET_USER="alice"
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR" "$SETUP_PACKAGES"
touch "$SETUP_LOG"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- A failing command aborts the run and writes no marker ------------------
log_stage_start packaging
# Subshell: run_logged exits on failure, which would end the test.
if (run_logged "simulated dnf failure" false) >/dev/null 2>&1; then
  fail "run_logged did not propagate a command failure"
fi
[[ ! -e "$SETUP_STATE_DIR/stage-packaging.done" ]] ||
  fail "failed stage wrote a completion marker"
grep -q "simulated dnf failure FAILED" "$SETUP_LOG" || fail "failure not logged"

# --- A missing command behaves the same way --------------------------------
if (run_logged "missing command" tophat-command-that-does-not-exist) >/dev/null 2>&1; then
  fail "run_logged did not fail on a missing command"
fi
[[ ! -e "$SETUP_STATE_DIR/stage-packaging.done" ]] ||
  fail "missing-command stage wrote a completion marker"

# --- So a rerun retries the same stage instead of skipping it ---------------
if stage_already_run packaging; then
  fail "stage with no marker was treated as complete"
fi

# --- Only after success does the marker appear ------------------------------
STAGE_STATUS[packaging]="running"
STAGE_DURATIONS[packaging]="$(date +%s)"
log_stage_complete packaging
[[ -f "$SETUP_STATE_DIR/stage-packaging.done" ]] || fail "successful stage wrote no marker"
[[ -f "$SETUP_STATE_DIR/stage-packaging.config" ]] || fail "no config snapshot saved"
if ! stage_already_run packaging; then
  fail "successful stage is not recognised on the next run"
fi

# --- An interruption between stages leaves the completed ones intact -------
log_stage_start services
# (no log_stage_complete: the run dies here)
[[ ! -e "$SETUP_STATE_DIR/stage-services.done" ]] ||
  fail "interrupted stage was marked complete"
[[ -f "$SETUP_STATE_DIR/stage-packaging.done" ]] ||
  fail "interruption lost the earlier stage's marker"

# --- A dry run records nothing at all --------------------------------------
DRY_RUN=true
STAGE_STATUS[repos]="running"
STAGE_DURATIONS[repos]="$(date +%s)"
log_stage_complete repos
[[ ! -e "$SETUP_STATE_DIR/stage-repos.done" ]] || fail "dry run wrote a marker"

echo "failure_recovery_test.sh: PASS"
