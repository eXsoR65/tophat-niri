#!/bin/bash
# =============================================================================
#  dms_setup_test.sh — 'dms setup' in the config stage must not hang
#
#  Regression test for the pipe-EOF deadlock: 'dms setup' spawning a
#  background child that inherits stdout used to block the installer forever
#  inside $(...). Output now goes to a file with stdin detached.
#
#  runuser and env are stubbed through PATH so the test runs unprivileged;
#  getent is stubbed so TARGET_USER_HOME points at a temp directory.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
DMS_CHILD_PID="$tmp_dir/child.pid"

cleanup() {
  if [[ -f "$DMS_CHILD_PID" ]]; then
    kill "$(cat "$DMS_CHILD_PID")" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib" SETUP_PACKAGES="$ROOT/packages"
export TARGET_USER
TARGET_USER="$(id -un)"
export SRC_FILE="$ROOT/lib/config/user_services.sh"
export DMS_CHILD_PID
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
export STUB_DIR="$stub_dir"

# getent: report a fake home inside the temp dir (avoid touching real $HOME)
cat >"$stub_dir/getent" <<'STUB'
#!/bin/bash
if [[ "$1" == "passwd" ]]; then
  echo "$2:x:$(id -u "$2"):$(id -g "$2")::${STUB_HOME:-/tmp}:/bin/bash"
  exit 0
fi
exit 2
STUB

# runuser: drop "--user USER --" and exec the remainder directly
cat >"$stub_dir/runuser" <<'STUB'
#!/bin/bash
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
[[ "${1:-}" == "--" ]] && shift
exec "$@"
STUB

# env: handle "-i" and VAR=val prefixes, keep the stub bin dir on PATH
cat >"$stub_dir/env" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "-i" ]] && shift
kv=()
while [[ $# -gt 0 && "$1" == *=* ]]; do
  kv+=("$1")
  shift
done
((${#kv[@]})) && export "${kv[@]}"
export PATH="$STUB_DIR:/usr/local/bin:/usr/bin:/bin"
exec "$@"
STUB

# dms: mimic a setup that spawns a long-lived background child holding stdout
cat >"$stub_dir/dms" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "setup" ]]; then
  sleep 30 &
  echo $! >"$DMS_CHILD_PID"
  echo "dms setup spawned a background child"
  exit 0
fi
exit 0
STUB

chmod +x "$stub_dir/getent" "$stub_dir/runuser" "$stub_dir/env" "$stub_dir/dms"
export PATH="$stub_dir:$PATH"
export STUB_HOME="$tmp_dir/fake-home"
mkdir -p "$STUB_HOME"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"

# Functions must survive into the timeout-bounded child shell below
export -f _log_write resolve_target_user log_info log_ok log_warn log_error target_user_command

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Config stage completes even when dms leaves a background child ----------
# timeout(1) bounds the source: the pre-fix code hangs on the grandchild's
# pipe here and gets killed after 15s.
rc=0
# $SRC_FILE is exported and intentionally expanded in the child shell
# shellcheck disable=SC2016
out="$(timeout 15 bash -c 'source "$SRC_FILE"' 2>&1)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "config stage did not complete (rc=$rc, 124=hang): $out"

grep -q "completed successfully" <<<"$out" ||
  grep -q "completed successfully" "$SETUP_LOG" ||
  fail "'dms setup' success not logged: $out"

# --- Fake home was configured, real HOME untouched ----------------------------
[[ -d "$STUB_HOME/.config/niri" ]] || fail "config dirs not created in target home"
[[ ! -e "$HOME/.config/niri" ]] || fail "test polluted real HOME"

echo "dms_setup_test.sh: PASS"
