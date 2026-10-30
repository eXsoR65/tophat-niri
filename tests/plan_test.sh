#!/bin/bash
# =============================================================================
#  plan_test.sh — `--print-plan` is the one place stage resolution is exposed
#
#  The TUI draws its plan preview by asking the installer, never by reimplementing
#  STAGE_DEPENDENCIES in TypeScript. That only stays true if this contract is
#  tested: one stage per line on stdout, dependency closure included, errors on
#  stderr with a non-zero status, and no root required.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

plan() {
  (cd "$ROOT" && ./install.sh --print-plan "$@" 2>"$tmp_dir/err")
}

# --- the default plan is every stage, in execution order --------------------
expected="preflight
repos
packaging
config
services
extras
finalize"
[[ "$(plan)" == "$expected" ]] || fail "default plan differs:\n$(plan)"

# --- a selection expands to its dependency closure --------------------------
[[ "$(plan --select config)" == "preflight
repos
packaging
config" ]] || fail "config did not pull its dependencies"

# --- dependency edges are the declared ones, not a guess -------------------
# finalize declares only preflight: its completeness is enforced at runtime by
# the marker guard in lib/finalize/all.sh, not by graph edges. Asserting the real
# shape keeps this test honest if the table changes.
[[ "$(plan --select finalize)" == "preflight
finalize" ]] || fail "finalize plan is not preflight+finalize"

[[ "$(plan --select services)" == "preflight
repos
packaging
config
services" ]] || fail "services did not pull its chain"

# --- selecting everything is the same as selecting nothing ------------------
[[ "$(plan --select preflight,repos,packaging,config,services,extras,finalize)" == "$expected" ]] ||
  fail "selecting every stage changed the plan"

# --- stdout stays machine-readable: no summary lines ------------------------
plan >"$tmp_dir/out" || fail "default plan failed"
if grep -q 'Execution plan\|Requested stages\|Warning' "$tmp_dir/out"; then
  fail "plan output contains human-readable noise: $(cat "$tmp_dir/out")"
fi

# A selective plan announces itself on stderr, never stdout.
plan --select config >"$tmp_dir/out2" || fail "selective plan failed"
if grep -q 'Execution plan\|Requested stages' "$tmp_dir/out2"; then
  fail "selective plan leaked its summary to stdout"
fi
grep -q 'Execution plan' "$tmp_dir/err" || fail "the summary should reach stderr"

# --- an unknown stage fails loudly, with nothing on stdout -----------------
if plan --select notastage >"$tmp_dir/out" 2>/dev/null; then
  fail "unknown stage was accepted"
fi
[[ -s "$tmp_dir/out" ]] && fail "failed plan still wrote to stdout"

# --- malformed selections are rejected here too -----------------------------
if plan --select "" >/dev/null 2>&1; then fail "empty --select was accepted"; fi
if plan --select "config," >/dev/null 2>&1; then fail "trailing comma was accepted"; fi

# --- no root required --------------------------------------------------------
# The plan is read-only, so it must work before the privilege check. The summary
# on stderr is expected; a root error is not.
if [[ "$(id -u)" -ne 0 ]]; then
  err="$(plan --select config 2>&1 >/dev/null)"
  [[ "$err" != *"must be run as root"* ]] || fail "--print-plan demanded root"
else
  echo "  (running as root; the privilege check is not exercised)"
fi

echo "plan_test.sh: PASS"
