#!/bin/bash
# =============================================================================
#  verify_all.sh — everything that must pass before pushing
#
#  CI runs the same gates on push, but a push that fails costs a round trip and
#  (worse) an unreviewed commit on the remote. Run this first:
#
#      tests/verify_all.sh
#
#  Set FAST=1 to skip the concurrency stress rounds while iterating.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() {
  printf '\n=== %s ===\n' "$*"
}

fail() {
  printf '\nFAILED: %s\n' "$*" >&2
  exit 1
}

step '1/7 bash syntax'
find . -path ./.git -prune -o -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n || fail 'bash -n'
bash -n install.sh || fail 'install.sh syntax'

step '2/7 shellcheck'
mapfile -t shell_files < <(find lib tests kickstart -type f -name '*.sh' | sort)
shellcheck -s bash -x -e SC1090,SC1091 install.sh "${shell_files[@]}" || fail 'shellcheck'

step '3/7 formatting (shfmt -i 2 -ci)'
shfmt -d -i 2 -ci install.sh lib tests kickstart || fail 'shfmt'

step '4/7 workflow actions pinned to SHAs'
tests/check_action_pins.sh || fail 'action pinning'

step '5/7 kickstart validation'
kickstart/validate-kickstart.sh || fail 'kickstart validator'

step '6/7 test suite'
for test_file in tests/*_test.sh; do
  printf '  %-34s ' "$(basename "$test_file")"
  if "$test_file" >/tmp/verify_test.log 2>&1; then
    echo PASS
  else
    echo FAIL
    tail -15 /tmp/verify_test.log
    fail "$test_file"
  fi
done

if [[ "${FAST:-0}" == 1 ]]; then
  step '7/7 lock concurrency (skipped: FAST=1)'
else
  step '7/7 lock concurrency stress'
  # The races this guards against only appear when processes interleave, which
  # the sequential tests above cannot produce.
  ROUNDS=5 WORKERS=12 tests/lock_concurrency_test.sh || fail 'lock concurrency'
fi

step 'version consistency'
version="$(<VERSION)"
header="$(sed -n '3s/.*Tophat v\([0-9][0-9.]*\).*/\1/p' install.sh)"
[[ "$version" == "$header" ]] || fail "VERSION (${version}) != install.sh header (${header})"
echo "  VERSION=${version} matches install.sh"

printf '\nAll checks passed.\n'
