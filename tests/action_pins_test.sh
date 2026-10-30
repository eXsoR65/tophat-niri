#!/bin/bash
# =============================================================================
#  action_pins_test.sh — the pin check must see every valid spelling
#
#  Each earlier version of the checker was blind to a spelling that appeared
#  later: indented `uses:`, then only double quotes, then only .yml files, then
#  flow mappings and folded scalars. It now parses YAML properly, and every shape
#  known to have caused a finding is a fixture here in both directions, so the
#  next one is a test change rather than another review round.
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

# expect_pass <name> <filename> <body>
expect_pass() {
  local name="$1" filename="$2" body="$3" dir="$tmp_dir/pass-$1"
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$body" >"$dir/.github/workflows/$filename"
  "$CHECK" "$dir" >/dev/null 2>&1 || fail "expected PASS for ${name}"
}

# expect_fail <name> <filename> <body> <expected fragment>
expect_fail() {
  local name="$1" filename="$2" body="$3" want="$4" dir="$tmp_dir/fail-$1" out
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$body" >"$dir/.github/workflows/$filename"
  if out="$("$CHECK" "$dir" 2>&1)"; then
    fail "expected FAIL for ${name}, got PASS"
  fi
  [[ "$out" == *"$want"* ]] || fail "expected '${want}' in output for ${name}, got: ${out}"
}

# --- pinned in each spelling -------------------------------------------------
expect_pass named w.yml "jobs:
  a:
    steps:
      - name: Checkout
        uses: actions/checkout@${SHA} # v7.0.1"

expect_pass unnamed w.yml "jobs:
  a:
    steps:
      - uses: actions/checkout@${SHA}"

expect_pass single-quoted w.yml "jobs:
  a:
    steps:
      - uses: 'actions/checkout@${SHA}'"

expect_pass double-quoted w.yml "jobs:
  a:
    steps:
      - uses: \"actions/checkout@${SHA}\""

# --- the other legal workflow extension --------------------------------------
expect_pass yaml-extension workflow.yaml "jobs:
  a:
    steps:
      - uses: actions/checkout@${SHA}"

# --- things that are not action references -----------------------------------
expect_pass local-action w.yml "jobs:
  a:
    steps:
      - uses: ./.github/actions/setup"

expect_pass container-image-digest w.yml "jobs:
  a:
    steps:
      - uses: docker://alpine@sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

expect_fail container-image-tag w.yml "jobs:
  a:
    steps:
      - uses: docker://alpine:3.20" "docker://alpine:3.20"

# A YAML alias is resolved by the parser, so the real reference is checked and
# named in the failure rather than being skipped as an unknown shape.
expect_fail yaml-alias w.yml "anchors:
  checkout: &checkout actions/checkout@v7
jobs:
  a:
    steps:
      - uses: *checkout" "actions/checkout@v7"

# A run block whose text contains "uses:" must not be read as a reference.
expect_pass uses-in-run-block w.yml "jobs:
  a:
    steps:
      - name: Explain
        run: |
          echo 'uses: actions/checkout@v7'
          echo done"

# ...even when the block is nested and uses the folded style.
expect_pass uses-in-folded-block w.yml "jobs:
  a:
    steps:
      - name: Explain
        shell: bash
        run: >
          cat <<'EOF'
          uses: actions/checkout@v7
          EOF"

# A blank line inside a run block belongs to the scalar, so the heredoc after it
# is still script text, not an action reference.
expect_pass blank-line-in-run-block w.yml "jobs:
  a:
    steps:
      - name: Explain
        run: |
          echo start

          cat <<'EOF'
          uses: actions/checkout@v7
          EOF"

# CRLF checkouts must behave identically (a stray carriage return would otherwise
# make a pinned ref unrecognisable).
expect_pass crlf-pinned crlf.yml "$(printf 'jobs:\r\n  a:\r\n    steps:\r\n      - uses: actions/checkout@%s\r\n' "$SHA")"
expect_fail crlf-unpinned crlf.yml "$(printf 'jobs:\r\n  a:\r\n    steps:\r\n      - uses: actions/checkout@v7\r\n')" "actions/checkout@v7"

# --- YAML representations a line scanner cannot handle -----------------------
# flow mapping
expect_pass flow-mapping w.yml "jobs:
  a:
    steps:
      - {uses: actions/checkout@${SHA}}"

# folded scalar value
expect_pass folded-value w.yml "jobs:
  a:
    steps:
      - uses: >-
          actions/checkout@${SHA}"

# quoted key
expect_pass quoted-key w.yml "jobs:
  a:
    steps:
      - \"uses\": actions/checkout@${SHA}"

# a block header carrying a trailing comment is still a block
expect_pass block-header-comment w.yml "jobs:
  a:
    steps:
      - name: Explain
        run: |  # Generate example configuration
          cat <<'EOF'
          uses: actions/checkout@v7
          EOF"

# --- and the same shapes unpinned -------------------------------------------
expect_fail flow-mapping-unpinned w.yml "jobs:
  a:
    steps:
      - {uses: actions/checkout@v7}" "actions/checkout@v7"

expect_fail folded-value-unpinned w.yml "jobs:
  a:
    steps:
      - uses: >-
          actions/checkout@v7" "actions/checkout@v7"

expect_fail quoted-key-unpinned w.yml "jobs:
  a:
    steps:
      - \"uses\": actions/checkout@v7" "actions/checkout@v7"

# --- unpinned in each spelling ----------------------------------------------
expect_fail named w.yml "jobs:
  a:
    steps:
      - name: Checkout
        uses: actions/checkout@v7" "actions/checkout@v7"

expect_fail unnamed w.yml "jobs:
  a:
    steps:
      - uses: actions/checkout@v7" "actions/checkout@v7"

expect_fail single-quoted w.yml "jobs:
  a:
    steps:
      - uses: 'actions/checkout@v7'" "actions/checkout@v7"

expect_fail double-quoted w.yml "jobs:
  a:
    steps:
      - uses: \"actions/checkout@v7\"" "actions/checkout@v7"

expect_fail branch-ref w.yml "jobs:
  a:
    steps:
      - uses: actions/checkout@main" "actions/checkout@main"

expect_fail yaml-extension workflow.yaml "jobs:
  a:
    steps:
      - uses: actions/checkout@v7" "actions/checkout@v7"

# --- a misconfigured root is an error, not a silent pass ---------------------
empty="$tmp_dir/empty"
mkdir -p "$empty/.github/workflows"
if "$CHECK" "$empty" >/dev/null 2>&1; then
  fail "expected FAIL when there are no workflow files"
fi

echo "action_pins_test.sh: PASS"
