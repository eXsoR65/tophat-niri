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

# --- Malformed --select lists are rejected ------------------------------------
# An empty value used to mean "no selection" = install everything, which is the
# opposite of what a script passing "" intends.
select_msg="--select expects comma-separated stage names"
expect_error "$select_msg" --select ""
expect_error "$select_msg" --select "repos,"
expect_error "$select_msg" --select ",repos"
expect_error "$select_msg" --select "repos,,config"

# --- Values that look like flags are rejected even when more args follow -----
expect_error "--select requires a comma-separated stage list" --select --force repos
expect_error "--target-user requires a username" --target-user --force alice

# --- --help prints usage and exits 0 -------------------------------------------
help_out="$(parse_args --help)"
grep -q "Available stages:" <<<"$help_out" || fail "--help did not print usage"
grep -q -- "--select STAGES" <<<"$help_out" || fail "--help missing --select docs"

short_help_out="$(parse_args -h)"
grep -q "Available stages:" <<<"$short_help_out" || fail "-h did not print usage"

# --- --version reports the version and exits 0 --------------------------------
expected_version="Tophat $(<"$ROOT/VERSION")"
version_out="$(SETUP_ROOT="$ROOT" parse_args --version)" || fail "--version exited non-zero"
[[ "$version_out" == "$expected_version" ]] ||
  fail "--version from VERSION file: expected '$expected_version', got: $version_out"

# install.sh exports TOPHAT_VERSION before sourcing; that must win when set
export TOPHAT_VERSION="9.9.9-test"
[[ "$(parse_args --version)" == "Tophat 9.9.9-test" ]] ||
  fail "--version ignored an exported TOPHAT_VERSION"
unset TOPHAT_VERSION

# Missing both sources degrades to "unknown" instead of erroring
[[ "$(parse_args --version)" == "Tophat unknown" ]] ||
  fail "--version without TOPHAT_VERSION or SETUP_ROOT should report 'unknown'"

# --- --version is documented in --help ----------------------------------------
grep -q -- "--version" <<<"$help_out" || fail "--help missing --version docs"

echo "arg_parse_test.sh: PASS"
