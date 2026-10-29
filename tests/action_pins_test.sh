#!/bin/bash
# =============================================================================
#  action_pins_test.sh — the pin check must see every valid spelling
#
#  tests/check_action_pins.sh has now been wrong twice in the same way: it only
#  recognised the spelling that existed when it was written (indented `uses:`,
#  then only double quotes). Each spelling YAML allows is a separate fixture
#  here, so adding one is a test change rather than a guess.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/tests/check_action_pins.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

SHA="0123456789abcdef0123456789abcdef01234567"

# expect_pass <name> <workflow body>
expect_pass() {
  local name="$1" body="$2" dir="$tmp_dir/pass-$1"
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$body" >"$dir/.github/workflows/w.yml"
  "$CHECK" "$dir" >/dev/null 2>&1 || fail "expected PASS for ${name}"
}

# expect_fail <name> <workflow body> <expected fragment>
expect_fail() {
  local name="$1" body="$2" want="$3" dir="$tmp_dir/fail-$1" out
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$body" >"$dir/.github/workflows/w.yml"
  if out="$("$CHECK" "$dir" 2>&1)"; then
    fail "expected FAIL for ${name}, got PASS"
  fi
  [[ "$out" == *"$want"* ]] || fail "expected '${want}' in output for ${name}, got: ${out}"
}

# --- pinned in each spelling -------------------------------------------------
expect_pass named "jobs:
  a:
    steps:
      - name: Checkout
        uses: actions/checkout@${SHA} # v7.0.1"

expect_pass unnamed "jobs:
  a:
    steps:
      - uses: actions/checkout@${SHA}"

expect_pass single-quoted "jobs:
  a:
    steps:
      - uses: 'actions/checkout@${SHA}'"

expect_pass double-quoted "jobs:
  a:
    steps:
      - uses: \"actions/checkout@${SHA}\""

# --- unpinned in each spelling ----------------------------------------------
UNPINNED="jobs:
  a:
    steps:
      - name: Checkout
        uses: actions/checkout@v7"
expect_fail named "$UNPINNED" "actions/checkout@v7"

expect_fail unnamed "jobs:
  a:
    steps:
      - uses: actions/checkout@v7" "actions/checkout@v7"

expect_fail single-quoted "jobs:
  a:
    steps:
      - uses: 'actions/checkout@v7'" "actions/checkout@v7"

expect_fail double-quoted "jobs:
  a:
    steps:
      - uses: \"actions/checkout@v7\"" "actions/checkout@v7"

expect_fail branch-ref "jobs:
  a:
    steps:
      - uses: actions/checkout@main" "actions/checkout@main"

# --- a local composite action has no ref to pin ------------------------------
expect_pass local-action "jobs:
  a:
    steps:
      - uses: ./.github/actions/setup"

echo "action_pins_test.sh: PASS"
