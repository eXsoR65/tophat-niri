#!/bin/bash
# =============================================================================
#  stage_resolution_test.sh — Dependency resolution from lib/stages.sh
#
#  Tests intentionally mutate the global STAGES plan inside subshells.
#  shellcheck disable=SC2030,SC2031
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/stages.sh
source "$ROOT/lib/stages.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Resolve a --select value in a clean subshell; prints the execution plan.
plan_for() {
  (
    SELECTIVE_STAGES="$1"
    STAGE_WANTED=()
    STAGES=()
    resolve_stages >/dev/null
    echo "${STAGES[*]}"
  )
}

# Resolve with no --select; prints the execution plan.
plan_default() {
  (
    SELECTIVE_STAGES=""
    STAGE_WANTED=()
    resolve_stages >/dev/null
    echo "${STAGES[*]}"
  )
}

# Expect resolution to fail; prints the error message.
plan_error() {
  (
    SELECTIVE_STAGES="$1"
    STAGE_WANTED=()
    STAGES=()
    resolve_stages >/dev/null
  )
}

# --- Canonical order and dependency pull-in ---
[[ "$(plan_for config)" == "preflight repos packaging config" ]] ||
  fail "config plan: $(plan_for config)"
[[ "$(plan_for services)" == "preflight repos packaging config services" ]] ||
  fail "services plan: $(plan_for services)"
[[ "$(plan_for extras)" == "preflight extras" ]] ||
  fail "extras plan: $(plan_for extras)"
[[ "$(plan_for finalize)" == "preflight finalize" ]] ||
  fail "finalize plan: $(plan_for finalize)"

# --- Ordering is canonical regardless of request order ---
[[ "$(plan_for "extras,repos")" == "preflight repos extras" ]] ||
  fail "out-of-order request: $(plan_for "extras,repos")"

# --- Duplicates are deduplicated ---
[[ "$(plan_for "config,packaging,config")" == "preflight repos packaging config" ]] ||
  fail "duplicate request: $(plan_for "config,packaging,config")"

# --- Surrounding whitespace is tolerated ---
[[ "$(plan_for " repos , packaging ")" == "preflight repos packaging" ]] ||
  fail "whitespace request: $(plan_for " repos , packaging ")"

# --- No selection runs everything ---
[[ "$(plan_default)" == "preflight repos packaging config services extras finalize" ]] ||
  fail "default plan: $(plan_default)"

# --- Invalid and empty stage names fail loudly ---
if msg="$(plan_error bogus 2>&1)"; then
  fail "invalid stage accepted"
fi
grep -q "invalid stage 'bogus'" <<<"$msg" || fail "unexpected invalid-stage message: $msg"

if msg="$(plan_error "repos,,config" 2>&1)"; then
  fail "empty stage entry accepted"
fi
grep -q "empty stage name" <<<"$msg" || fail "unexpected empty-stage message: $msg"

# --- Dependency cycles abort instead of recursing forever ---
cycle_result="$(
  (
    STAGE_DEPENDENCIES[repos]="packaging"
    STAGE_DEPENDENCIES[packaging]="repos"
    stage_add_with_dependencies repos
    echo "RESOLVED"
  ) 2>&1 || true
)"
grep -q "circular stage dependency detected" <<<"$cycle_result" ||
  fail "direct cycle not detected: $cycle_result"

self_cycle_result="$(
  (
    STAGE_DEPENDENCIES[extras]="extras"
    stage_add_with_dependencies extras
    echo "RESOLVED"
  ) 2>&1 || true
)"
grep -q "circular stage dependency detected" <<<"$self_cycle_result" ||
  fail "self cycle not detected: $self_cycle_result"

echo "stage_resolution_test.sh: PASS"
