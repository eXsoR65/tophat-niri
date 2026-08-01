#!/bin/bash
# =============================================================================
#  pkg_test.sh — Package helper behavior (lib/helpers/pkg.sh)
#
#  rpm and dnf are stubbed through PATH; the stub "installed" set lives in
#  $MOCK_INSTALLED (one package name per line).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

# --- Command stubs -----------------------------------------------------------
MOCK_INSTALLED="$tmp_dir/installed"
DNF_CALLS="$tmp_dir/dnf-calls"
export MOCK_INSTALLED DNF_CALLS
: >"$MOCK_INSTALLED"
: >"$DNF_CALLS"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"

cat >"$stub_dir/rpm" <<'STUB'
#!/bin/bash
# rpm -q <pkg> succeeds only for packages in the mock installed set
if [[ "$1" == "-q" ]]; then
  grep -qxF "$2" "$MOCK_INSTALLED" && exit 0 || exit 1
fi
exit 0
STUB

cat >"$stub_dir/dnf" <<'STUB'
#!/bin/bash
echo "$*" >>"$DNF_CALLS"
exit 0
STUB

chmod +x "$stub_dir/rpm" "$stub_dir/dnf"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- pkg_install skips already-installed packages ----------------------------
printf 'alfa\n' >"$MOCK_INSTALLED"
: >"$DNF_CALLS"
pkg_install alfa >/dev/null
[[ ! -s "$DNF_CALLS" ]] || fail "dnf called for already-installed package: $(cat "$DNF_CALLS")"
grep -q "All packages already installed" "$SETUP_LOG" || fail "skip not logged"

# --- pkg_install installs only the missing ones ------------------------------
printf 'alfa\n' >"$MOCK_INSTALLED"
: >"$DNF_CALLS"
pkg_install alfa beta >/dev/null
[[ "$(cat "$DNF_CALLS")" == "install -y beta" ]] ||
  fail "dnf called with wrong set: $(cat "$DNF_CALLS")"

# --- pkg_remove with nothing present is a no-op ------------------------------
: >"$MOCK_INSTALLED"
: >"$DNF_CALLS"
pkg_remove ghost >/dev/null
[[ ! -s "$DNF_CALLS" ]] || fail "dnf remove called for absent package"
grep -q "Nothing to remove" "$SETUP_LOG" || fail "remove no-op not logged"

# --- pkg_remove refuses without confirmation (no TTY, no flag) ---------------
printf 'mako\nwaybar\n' >"$MOCK_INSTALLED"
: >"$DNF_CALLS"
if pkg_remove mako </dev/null >/dev/null 2>&1; then
  fail "pkg_remove proceeded without confirmation"
fi
[[ ! -s "$DNF_CALLS" ]] || fail "dnf remove called despite refusal"
grep -q -- "--accept-package-removals" "$SETUP_LOG" || fail "refusal guidance not logged"

# --- pkg_remove honors ACCEPT_PACKAGE_REMOVALS and writes a manifest ---------
printf 'mako\nwaybar\n' >"$MOCK_INSTALLED"
: >"$DNF_CALLS"
ACCEPT_PACKAGE_REMOVALS=true pkg_remove mako waybar >/dev/null
[[ "$(cat "$DNF_CALLS")" == "remove -y mako waybar" ]] ||
  fail "dnf remove called with wrong set: $(cat "$DNF_CALLS")"
manifest_count="$(find "$SETUP_STATE_DIR/manifests" -type f | wc -l)"
[[ "$manifest_count" -eq 1 ]] || fail "no removal manifest written"
grep -qxF mako "$SETUP_STATE_DIR"/manifests/removed-packages-*.txt ||
  fail "manifest missing removed package"

# --- Dry run never invokes dnf and writes no manifest -----------------------
: >"$DNF_CALLS"
manifests_before="$(find "$SETUP_STATE_DIR/manifests" -type f | wc -l)"
if ! DRY_RUN=true pkg_remove mako >/dev/null; then
  fail "dry-run removal failed"
fi
[[ ! -s "$DNF_CALLS" ]] || fail "dnf called during dry run"
manifests_after="$(find "$SETUP_STATE_DIR/manifests" -type f | wc -l)"
[[ "$manifests_after" == "$manifests_before" ]] ||
  fail "manifest written during dry run"

echo "pkg_test.sh: PASS"
