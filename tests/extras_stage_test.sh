#!/bin/bash
# =============================================================================
#  extras_stage_test.sh — Extras stage gating and input validation
#
#  SETUP_PACKAGES points at a temp directory so opt-in files are created and
#  removed without touching the repository. Validation happens before any
#  user resolution or package install, so no root or dnf is needed here.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib"
export SETUP_PACKAGES="$tmp_dir/packages"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR" "$SETUP_PACKAGES"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"
# shellcheck source=lib/extras/all.sh
source "$ROOT/lib/extras/all.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- No opt-in files: the stage is skipped without writing a marker ---------
run_extras_stage >/dev/null
grep -q "No optional extras are enabled" "$SETUP_LOG" || fail "skip reason not logged"
[[ ! -e "$SETUP_STATE_DIR/stage-extras.done" ]] ||
  fail "skipped extras stage wrote a completion marker"

# --- An invalid Flatpak ID aborts before anything is installed --------------
printf 'org.example.App\nnot-a-flatpak-id\n' >"$SETUP_PACKAGES/flatpaks.packages"
# Subshell: the stage calls exit 1, which would end the test.
if out="$( (run_extras_stage) 2>&1)"; then
  fail "invalid Flatpak ID was accepted"
fi
grep -q "Invalid Flatpak application ID" <<<"$out" || fail "missing Flatpak error: $out"
[[ ! -e "$SETUP_STATE_DIR/stage-extras.done" ]] ||
  fail "failed extras stage wrote a completion marker"
rm -f "$SETUP_PACKAGES/flatpaks.packages"

# --- An invalid Homebrew formula aborts before anything is installed -------
printf 'ripgrep\nbad formula with spaces\n' >"$SETUP_PACKAGES/homebrew.packages"
if out="$( (run_extras_stage) 2>&1)"; then
  fail "invalid Homebrew formula was accepted"
fi
grep -q "Invalid Homebrew formula" <<<"$out" || fail "missing formula error: $out"
rm -f "$SETUP_PACKAGES/homebrew.packages"

# --- A distrobox opt-in file routes into the distrobox sub-script -----------
: >"$SETUP_PACKAGES/distrobox.enable"
: >"$SETUP_LOG"
# No non-root target user exists here, so the stage must fail at resolution
# rather than silently claiming success.
if (run_extras_stage) >/dev/null 2>&1; then
  fail "distrobox opt-in did not require a target user"
fi
grep -q "Could not resolve the target user for Distrobox" "$SETUP_LOG" ||
  fail "distrobox resolution failure not logged"

echo "extras_stage_test.sh: PASS"
