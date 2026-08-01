#!/bin/bash
# =============================================================================
#  arg_parse_test.sh — CLI parsing from lib/stages.sh
#
#  parse_args is exercised in subshells because it exits on bad input and on
#  --help.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/stages.sh
source "$ROOT/lib/stages.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Flags are applied -------------------------------------------------------
(
  parse_args --dry-run --force --verbose --accept-package-removals
  [[ "$DRY_RUN" == true ]] || exit 1
  [[ "$FORCE" == true ]] || exit 1
  [[ "$VERBOSE" == true ]] || exit 1
  [[ "$ACCEPT_PACKAGE_REMOVALS" == true ]] || exit 1
) || fail "boolean flags not applied"

# --- --select and --target-user store values ---------------------------------
(
  parse_args --select "repos,packaging" --target-user alice
  [[ "$SELECTIVE_STAGES" == "repos,packaging" ]] || exit 1
  [[ "$TARGET_USER" == "alice" ]] || exit 1
) || fail "valued options not stored"

# --- No arguments keeps defaults ----------------------------------------------
(
  parse_args
  [[ "$DRY_RUN" == false ]] || exit 1
  [[ "$FORCE" == false ]] || exit 1
  [[ -z "$SELECTIVE_STAGES" ]] || exit 1
) || fail "defaults disturbed with no args"

# --- Missing values are rejected ----------------------------------------------
expect_error() { # $1 = expected message, rest = args
  local expected="$1"
  shift
  local msg
  if msg="$(parse_args "$@" 2>&1)"; then
    fail "parse_args $* unexpectedly succeeded"
  fi
  grep -q -- "$expected" <<<"$msg" || fail "parse_args $*: expected '$expected', got: $msg"
}

expect_error "--select requires a comma-separated stage list" --select
expect_error "--select requires a comma-separated stage list" --select --force
expect_error "--target-user requires a username" --target-user
expect_error "--target-user requires a username" --target-user --verbose
expect_error "Unknown option: --bogus" --bogus
expect_error "Unknown option: -x" -x

# --- Values that look like flags are rejected even when more args follow -----
expect_error "--select requires a comma-separated stage list" --select --force repos
expect_error "--target-user requires a username" --target-user --force alice

# --- --help prints usage and exits 0 -------------------------------------------
help_out="$(parse_args --help)"
grep -q "Available stages:" <<<"$help_out" || fail "--help did not print usage"
grep -q -- "--select STAGES" <<<"$help_out" || fail "--help missing --select docs"

short_help_out="$(parse_args -h)"
grep -q "Available stages:" <<<"$short_help_out" || fail "-h did not print usage"

echo "arg_parse_test.sh: PASS"
