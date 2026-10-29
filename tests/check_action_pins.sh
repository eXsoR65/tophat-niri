#!/bin/bash
# =============================================================================
#  check_action_pins.sh — every remote action must be pinned to a commit SHA
#
#  A tag can be moved; a 40-character commit SHA cannot. Dependabot raises the
#  PRs that bump them, so pins stay current instead of fossilising.
#
#  Shared by CI and tests/verify_all.sh so the rule has exactly one
#  implementation. Local composite actions (`uses: ./.github/...`) have no ref to
#  pin and are ignored.
#
#  Usage: check_action_pins.sh [repo-root]
#  The optional root lets tests/action_pins_test.sh point this at fixtures.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$ROOT}"

# Matches a real `uses:` line in every spelling YAML allows for a step:
#   - uses: owner/action@ref          (unnamed step, sequence marker)
#       uses: owner/action@ref        (named step, indented)
#   - uses: 'owner/action@ref'        (single quoted)
#   - uses: "owner/action@ref"        (double quoted)
# \047 is a single quote, which keeps the awk program free of quoting puzzles.
unpinned="$(awk '
  /^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*/ {
    line = $0
    sub(/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*/, "", line)
    split(line, parts, /[[:space:]]/)
    ref = parts[1]
    gsub(/["\047]/, "", ref)
    if (ref ~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@/) print ref
  }
' .github/workflows/*.yml | grep -vE '@[0-9a-f]{40}$' || true)"

if [[ -n "$unpinned" ]]; then
  echo "FAIL: actions must be pinned to a 40-character commit SHA:" >&2
  while IFS= read -r ref; do
    printf '  %s\n' "$ref" >&2
  done <<<"$unpinned"
  exit 1
fi

echo "check_action_pins.sh: PASS"
