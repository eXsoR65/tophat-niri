#!/bin/bash
# =============================================================================
#  repos_stage_test.sh — Repository stage wiring
#
#  dnf, rpm and systemctl are stubbed through PATH. Asserts that RPM Fusion,
#  Brave and the three COPRs are enabled, and that metadata is refreshed once
#  for the whole stage rather than once per sub-script.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib" SETUP_PACKAGES="$ROOT/packages"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
export NETWORK_OK=true
export NIRI_COPR="yalter/niri" DMS_COPR="avengemedia/dms" GHOSTTY_COPR="scottames/ghostty"
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

DNF_CALLS="$tmp_dir/dnf-calls"
export DNF_CALLS
: >"$DNF_CALLS"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"

cat >"$stub_dir/dnf" <<'STUB'
#!/bin/bash
echo "$*" >>"$DNF_CALLS"
exit 0
STUB

cat >"$stub_dir/rpm" <<'STUB'
#!/bin/bash
# -E %fedora reports a release; -q reports nothing installed
if [[ "$1" == "-E" ]]; then
  echo "44"
  exit 0
fi
exit 1
STUB

chmod +x "$stub_dir/dnf" "$stub_dir/rpm"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"
# shellcheck source=lib/repos/all.sh
source "$ROOT/lib/repos/all.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Full run enables every repository ---------------------------------------
run_repos_stage >/dev/null

grep -q "copr enable -y yalter/niri" "$DNF_CALLS" || fail "niri COPR not enabled"
grep -q "copr enable -y avengemedia/dms" "$DNF_CALLS" || fail "DMS COPR not enabled"
grep -q "copr enable -y scottames/ghostty" "$DNF_CALLS" || fail "ghostty COPR not enabled"
grep -q "config-manager addrepo --from-repofile=https://brave-browser-rpm-release" "$DNF_CALLS" ||
  fail "Brave repository not added"
grep -q "rpmfusion-free-release-44.noarch.rpm" "$DNF_CALLS" ||
  fail "RPM Fusion free release not installed for Fedora 44"
grep -q "rpmfusion-nonfree-release-44.noarch.rpm" "$DNF_CALLS" ||
  fail "RPM Fusion nonfree release not installed for Fedora 44"

# --- Metadata is refreshed exactly once for the whole stage -------------------
makecache_count="$(grep -c "makecache" "$DNF_CALLS" || true)"
[[ "$makecache_count" -eq 1 ]] ||
  fail "expected exactly one dnf makecache, got $makecache_count"

# --- The stage marker short-circuits a re-run --------------------------------
date '+%Y-%m-%d %H:%M:%S' >"$SETUP_STATE_DIR/stage-repos.done"
: >"$DNF_CALLS"
run_repos_stage >/dev/null
[[ ! -s "$DNF_CALLS" ]] || fail "marked stage still called dnf: $(cat "$DNF_CALLS")"

echo "repos_stage_test.sh: PASS"
