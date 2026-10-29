#!/bin/bash
# =============================================================================
#  check_action_pins.sh — everything a workflow executes must be immutable
#
#  A tag can be moved; a 40-character commit SHA cannot. Dependabot raises the
#  PRs that bump them, so pins stay current instead of fossilising.
#
#  Shared by CI and tests/verify_all.sh so the rule has exactly one
#  implementation.
#
#  Usage: check_action_pins.sh [repo-root]
#  The optional root lets tests/action_pins_test.sh point this at fixtures.
#
#  The rule is an allowlist, not a pattern match. Earlier versions only inspected
#  references whose shape they recognised, so every unrecognised shape was
#  silently skipped - an unnamed step, a single-quoted value, a .yaml file, a
#  YAML alias. Now a `uses:` value is allowed only when it is:
#     - a local action (starts with ./ or ../), or
#     - a container image pinned by digest (docker://...@sha256:...), or
#     - a repository reference pinned to a 40-character commit SHA
#  Anything else fails, including shapes nobody anticipated.
#
#  Block scalars (`run: |`) are skipped: their text can contain "uses:" without
#  being an action reference.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-$ROOT}"

workflows=()
while IFS= read -r file; do
  workflows+=("$file")
done < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)

if ((${#workflows[@]} == 0)); then
  echo "FAIL: no workflow files found under $(pwd)/.github/workflows" >&2
  exit 1
fi

refs="$(awk '
  function indent_of(s,   m) {
    m = match(s, /^[[:space:]]*/)
    return m ? RLENGTH : 0
  }

  {
    ind = indent_of($0)

    # Inside a block scalar, skip everything indented deeper than the marker.
    if (in_block) {
      if (ind > block_indent) next
      in_block = 0
    }

    # Opening of a block scalar: key: |, key: >, with optional chomping or an
    # explicit indentation indicator.
    if ($0 ~ /^[[:space:]]*(-[[:space:]]+)?[A-Za-z0-9_.-]+:[[:space:]]*[|>][-+]?[0-9]?[[:space:]]*$/) {
      in_block = 1
      block_indent = ind
      next
    }

    if ($0 !~ /^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*/) next

    line = $0
    sub(/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*/, "", line)
    split(line, parts, /[[:space:]]/)
    ref = parts[1]

    # Strip quotes of either style; \047 is a single quote.
    gsub(/["\047]/, "", ref)
    print ref
  }
' "${workflows[@]}")"

bad=()
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  case "$ref" in
    ./* | ../*) continue ;; # local action, nothing to pin
    docker://*)
      # A tag can move; a digest cannot.
      [[ "$ref" == *"@sha256:"* ]] && continue
      ;;
    *)
      [[ "$ref" =~ @[0-9a-f]{40}$ ]] && continue
      ;;
  esac
  bad+=("$ref")
done <<<"$refs"

if ((${#bad[@]} > 0)); then
  echo "FAIL: workflow references must be pinned (40-character commit SHA, or a docker digest):" >&2
  for ref in "${bad[@]}"; do
    printf '  %s\n' "$ref" >&2
  done
  exit 1
fi

printf 'check_action_pins.sh: PASS (%d workflow file(s), %d reference(s))\n' \
  "${#workflows[@]}" "$(grep -c . <<<"$refs" || true)"
