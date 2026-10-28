#!/bin/bash
# =============================================================================
#  services_stage_test.sh — Greeter configuration and service stage wiring
#
#  write_greetd_config takes an explicit path, so the backup/no-clobber logic is
#  tested against a temp file. systemctl and rpm are stubbed through PATH.
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
mkdir -p "$SETUP_STATE_DIR"
touch "$SETUP_LOG"

SYSTEMCTL_CALLS="$tmp_dir/systemctl-calls"
export SYSTEMCTL_CALLS
: >"$SYSTEMCTL_CALLS"

stub_dir="$tmp_dir/bin"
mkdir -p "$stub_dir"
cat >"$stub_dir/systemctl" <<'STUB'
#!/bin/bash
echo "$*" >>"$SYSTEMCTL_CALLS"
exit 0
STUB
printf '#!/bin/bash\nexit 1\n' >"$stub_dir/rpm"
chmod +x "$stub_dir/systemctl" "$stub_dir/rpm"
export PATH="$stub_dir:$PATH"

# shellcheck source=lib/helpers/run_logged.sh
source "$ROOT/lib/helpers/run_logged.sh"
# shellcheck source=lib/helpers/checks.sh
source "$ROOT/lib/helpers/checks.sh"
# shellcheck source=lib/services/all.sh
source "$ROOT/lib/services/all.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

expected_config="$tmp_dir/expected.toml"
_greetd_config_body >"$expected_config"
config_file="$tmp_dir/config.toml"

# --- A fresh config is written ------------------------------------------------
write_greetd_config "$config_file" >/dev/null
[[ "$(<"$expected_config")" == "$(<"$config_file")" ]] || fail "greeter config content wrong"
find "$tmp_dir" -name 'config.toml.tophat-backup.*' | grep -q . &&
  fail "backup created when there was nothing to preserve"

# --- Re-running is a no-op ----------------------------------------------------
: >"$SETUP_LOG"
write_greetd_config "$config_file" >/dev/null
grep -q "already up to date" "$SETUP_LOG" || fail "idempotent write not detected"
find "$tmp_dir" -name 'config.toml.tophat-backup.*' | grep -q . &&
  fail "backup created for an identical config"

# --- A hand-edited config is preserved, not clobbered -------------------------
custom_config="$tmp_dir/custom/config.toml"
mkdir -p "$(dirname "$custom_config")"
printf '[terminal]\nvt = 7\n# my own customisation\n' >"$custom_config"

: >"$SETUP_LOG"
write_greetd_config "$custom_config" >/dev/null

backup="$(find "$(dirname "$custom_config")" -name 'config.toml.tophat-backup.*' | head -1)"
[[ -n "$backup" ]] || fail "custom greeter config was not backed up"
grep -q "my own customisation" "$backup" || fail "backup does not hold the original content"
[[ "$(<"$expected_config")" == "$(<"$custom_config")" ]] || fail "custom config was not replaced"
grep -q "backed up" "$SETUP_LOG" || fail "backup not logged"

# --- PAM hooks are added per missing hook, with a backup --------------------
pam_file="$tmp_dir/pam/greetd"
mkdir -p "$(dirname "$pam_file")"
printf '#%%PAM-1.0\nauth       include      system-auth\n-auth optional pam_gnome_keyring.so\n' >"$pam_file"

ensure_pam_keyring_hooks "$pam_file" >/dev/null
grep -qF -- '-session optional pam_gnome_keyring.so auto_start' "$pam_file" ||
  fail "missing session hook not added"
grep -qF -- '-password optional pam_gnome_keyring.so use_authtok' "$pam_file" ||
  fail "missing password hook not added"
grep -qF -- 'auth       include      system-auth' "$pam_file" ||
  fail "existing PAM content was not preserved"
pam_backups="$(find "$(dirname "$pam_file")" -name 'greetd.tophat-backup.*' | wc -l)"
[[ "$pam_backups" -eq 1 ]] || fail "PAM file not backed up exactly once (got $pam_backups)"

# Second run adds nothing and creates no further backup
: >"$SETUP_LOG"
ensure_pam_keyring_hooks "$pam_file" >/dev/null
pam_backups_after="$(find "$(dirname "$pam_file")" -name 'greetd.tophat-backup.*' | wc -l)"
[[ "$pam_backups_after" -eq 1 ]] || fail "second PAM run created another backup"
grep -q "already has all gnome-keyring hooks" "$SETUP_LOG" || fail "PAM idempotency not logged"

# --- A completed stage is skipped --------------------------------------------
date '+%Y-%m-%d %H:%M:%S' >"$SETUP_STATE_DIR/stage-services.done"
: >"$SYSTEMCTL_CALLS"
run_services_stage >/dev/null
[[ ! -s "$SYSTEMCTL_CALLS" ]] || fail "marked stage still called systemctl"

# --- Missing dms-greeter refuses instead of writing a broken greeter --------
# The marker must go, or the stage would short-circuit before the check.
rm -f "$SETUP_STATE_DIR/stage-services.done"
# Subshell: the stage calls exit 1, which would end the test.
if (run_services_stage) >/dev/null 2>&1; then
  fail "services stage proceeded without dms-greeter"
fi

echo "services_stage_test.sh: PASS"
