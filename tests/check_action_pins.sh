#!/bin/bash
# =============================================================================
#  check_action_pins.sh — every action must be pinned to a commit SHA
#
#  A tag can be moved; a 40-character commit SHA cannot. Dependabot raises the
#  PRs that bump them, so pins stay current instead of fossilising.
#
#  Shared by CI and tests/verify_all.sh so the rule has exactly one
#  implementation. Local composite actions (`uses: ./.github/...`) have no ref
#  to pin and are ignored.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Matches a real `uses:` line, including a step written without a `name`
# (`- uses: owner/action@ref`) and an optionally quoted value.
unpinned="$(awk '
  /^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*"?[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@/ {
    line = $0
    sub(/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*/, "", line)
    gsub(/"/, "", line)
    split(line, parts, /[[:space:]]/)
    print parts[1]
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
