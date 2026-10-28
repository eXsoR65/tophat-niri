#!/bin/bash
# =============================================================================
#  config_stage_test.sh — Config stage behavior (lib/config/user_services.sh)
#
#  Guards the decision that the installer never runs 'dms setup' (it requires
#  a graphical session and only ever hung or failed from a root context):
#  a stub dms acts as a tripwire, and the post-login guidance must be logged.
#
#  getent, id and chown are stubbed through PATH, and the target user is a
#  fixed fake account, so the outcome does not depend on who runs the test —
#  root inside a CI container has no non-root account to resolve to.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export SETUP_LOG="$tmp_dir/setup.log"
export SETUP_STATE_DIR="$tmp_dir/state"
export DRY_RUN=false VERBOSE=false FORCE=false ACCEPT_PACKAGE_REMOVALS=false
export CLR_RED='' CLR_GREEN='' CLR_YELLOW='' CLR_BLUE='' CLR_BOLD='' CLR_RESET=''
export SETUP_ROOT="$ROOT" SETUP_LIB="$ROOT/lib" SETUP_PACKAGES="$ROOT/packages"

# A fixed non-root target user, so the result does not depend on who runs the
# suite. Root inside a CI container has no non-root account with a real home,
# and resolve_target_user rightly refuses to guess in that case.
TEST_USER="tophat-test-user"
export TARGET_USER="$TEST_USER"
export CHOWN_CALLS="$tmp_dir/chown-calls"
REAL_ID="$(command -v id)"
export SRC_FILE="$ROOT/lib/config/user_services.sh"
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
export STUB_HOME="$tmp_dir/fake-home"
export DMS_TRIPWIRE="$tmp_dir/dms-was-called"
export XDG_USER_DIRS_CALL="$tmp_dir/xdg-user-dirs-call"
mkdir -p "$STUB_HOME"

# getent: report a fake home inside the temp dir (avoid touching real $HOME)
cat >"$stub_dir/getent" <<'STUB'
#!/bin/bash
if [[ "$1" == "passwd" ]]; then
  echo "$2:x:1000:1000::${STUB_HOME:-/tmp}:/bin/bash"
  exit 0
fi
exit 2
STUB

# id: the fake target user must "exist" for resolve_target_user; anything else
# is delegated to the real id so unrelated lookups keep working.
cat >"$stub_dir/id" <<STUB
#!/bin/bash
if [[ "\${1:-}" == "$TEST_USER" ]]; then
  exit 0
fi
exec "$REAL_ID" "\$@"
STUB

# chown: root-only side effect. Record the call and assert on it below instead
# of requiring the test process to be root or to own a real account.
cat >"$stub_dir/chown" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CHOWN_CALLS"
exit 0
STUB

# dms: tripwire — the config stage must never invoke dms
cat >"$stub_dir/dms" <<'STUB'
#!/bin/bash
echo "called with: $*" >"$DMS_TRIPWIRE"
exit 0
STUB

# xdg-user-dirs-update: record the user environment and model its directory creation
cat >"$stub_dir/xdg-user-dirs-update" <<'STUB'
#!/bin/bash
printf '%s|%s|%s\n' "$HOME" "$USER" "$*" >"$XDG_USER_DIRS_CALL"
mkdir -p \
  "$HOME/Desktop" \
  "$HOME/Documents" \
  "$HOME/Downloads" \
  "$HOME/Music" \
  "$HOME/Pictures" \
  "$HOME/Public" \
  "$HOME/Templates" \
  "$HOME/Videos"
STUB

chmod +x "$stub_dir/getent" "$stub_dir/id" "$stub_dir/chown" \
  "$stub_dir/dms" "$stub_dir/xdg-user-dirs-update"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/helpers/pkg.sh
source "$ROOT/lib/helpers/pkg.sh"

# Exercise run_as_target_user without requiring root in the test process.
target_user_command() {
  env -i \
    "HOME=$TARGET_USER_HOME" \
    "USER=$TARGET_USER" \
    "LOGNAME=$TARGET_USER" \
    "PATH=$stub_dir:$PATH" \
    "XDG_USER_DIRS_CALL=$XDG_USER_DIRS_CALL" \
    "$@"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Config stage completes and never calls dms -------------------------------
source "$SRC_FILE"

[[ ! -e "$DMS_TRIPWIRE" ]] ||
  fail "config stage invoked dms: $(cat "$DMS_TRIPWIRE")"

grep -q "Skipping 'dms setup'" "$SETUP_LOG" ||
  fail "post-login 'dms setup' guidance not logged"

# --- XDG package is installed and directories are initialized as target user -
grep -qxF "xdg-user-dirs" "$SETUP_PACKAGES/desktop-support.packages" ||
  fail "xdg-user-dirs missing from desktop support packages"
[[ "$(cat "$XDG_USER_DIRS_CALL")" == "${STUB_HOME}|${TARGET_USER}|" ]] ||
  fail "xdg-user-dirs-update did not run with the target user's environment"

for user_dir in Desktop Documents Downloads Music Pictures Public Templates Videos; do
  [[ -d "$STUB_HOME/$user_dir" ]] || fail "$user_dir was not created in target home"
done

# --- Fake home was configured, real HOME untouched ----------------------------
[[ -d "$STUB_HOME/.config/niri" ]] || fail "config dirs not created in target home"
[[ -d "$STUB_HOME/.config/environment.d" ]] ||
  fail "environment.d not created in target home"
[[ ! -e "$HOME/.config/niri" ]] || fail "test polluted real HOME"

# Ownership goes to the resolved target user, not to whoever ran the test
grep -qF "${TEST_USER}:${TEST_USER}" "$CHOWN_CALLS" ||
  fail "config dirs were not chowned to the target user"

# --- Missing dms.service warns instead of failing -----------------------------
grep -q "Could not find dms.service" "$SETUP_LOG" ||
  fail "missing dms.service did not produce a warning"

# --- Dry run reports but does not execute xdg-user-dirs-update ----------------
rm -f "$XDG_USER_DIRS_CALL"
DRY_RUN=true
source "$SRC_FILE" >/dev/null
[[ ! -e "$XDG_USER_DIRS_CALL" ]] || fail "xdg-user-dirs-update ran during dry run"

echo "config_stage_test.sh: PASS"
