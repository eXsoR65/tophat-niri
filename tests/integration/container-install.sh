#!/bin/bash
# =============================================================================
#  container-install.sh — real install inside a disposable Fedora container
#
#  Runs as root in a systemd-capable container (see
#  .github/workflows/integration.yml). Unlike tests/*_test.sh, this performs
#  actual dnf transactions against real repositories and then asserts the
#  resulting system state, idempotency and marker invalidation.
#
#  Deliberately out of scope here: anything needing a graphical session,
#  DRM/GPU or a reboot. See docs/INTEGRATION-TESTING.md.
# =============================================================================
set -euo pipefail

REPO_DIR="${REPO_DIR:-/src}"
TARGET_USER="${TARGET_USER:-tophat-it}"
EXTRA_PACKAGE="${EXTRA_PACKAGE:-tmux}"
STATE_DIR="/var/lib/tophat"

cd "$REPO_DIR"
VERSION="$(<VERSION)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

note() {
  printf '\n=== %s ===\n' "$*"
}

log_lines() {
  tail -40 /var/log/tophat/latest.log 2>/dev/null || true
}

trap 'status=$?; ((status == 0)) || log_lines' ERR

note "Tophat ${VERSION}: real install for user ${TARGET_USER}"
id "$TARGET_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$TARGET_USER"

./install.sh --verbose --accept-package-removals --target-user "$TARGET_USER"

note 'Completion state'
[[ -f "$STATE_DIR/.completed" ]] || fail '.completed was not written'
grep -qx "version=${VERSION}" "$STATE_DIR/.completed" ||
  fail ".completed does not record version ${VERSION}"

for stage in preflight repos packaging config services finalize; do
  marker="$STATE_DIR/stage-${stage}.done"
  [[ -f "$marker" ]] || fail "stage ${stage} has no marker"
  if ! grep -q '^version=' "$marker"; then
    fail "stage ${stage} marker records no version: this branch predates the
configuration-aware markers added in v2.7. Dispatch this workflow against dev
(or a newer branch) - the assertions below describe that behaviour."
  fi
  grep -qx "version=${VERSION}" "$marker" || fail "stage ${stage} marker has the wrong version"
  grep -qx "user=${TARGET_USER}" "$marker" || fail "stage ${stage} marker has the wrong user"
  [[ -f "$STATE_DIR/stage-${stage}.config" ]] || fail "stage ${stage} has no config snapshot"
done

note 'Services stage actually took effect'
systemctl is-enabled greetd.service >/dev/null || fail 'greetd.service is not enabled'
grep -q 'dms-greeter --command niri' /etc/greetd/config.toml ||
  fail '/etc/greetd/config.toml does not point at the DMS greeter'
grep -q 'pam_gnome_keyring.so use_authtok' /etc/pam.d/greetd ||
  fail 'the PAM password hook was not added'
ls /etc/pam.d/greetd.tophat-backup.* >/dev/null 2>&1 ||
  fail 'PAM was modified without a backup'

note 'Real packages are installed'
for pkg in niri dms dms-greeter; do
  rpm -q "$pkg" >/dev/null || fail "package ${pkg} is not installed"
done

note 'A second run must skip every completed stage'
./install.sh --verbose --accept-package-removals --target-user "$TARGET_USER" \
  >/tmp/tophat-rerun.log 2>&1 || fail 'second run failed'
for stage in repos packaging config services; do
  grep -q "Skipped stage: ${stage}" /tmp/tophat-rerun.log ||
    fail "second run re-ran stage ${stage}"
done
grep -q 'Preflight update already completed' /tmp/tophat-rerun.log ||
  fail 'second run repeated the system update'

note 'A changed package selection must invalidate the packaging stage'
printf '\n%s\n' "$EXTRA_PACKAGE" >>packages/desktop-support.packages
./install.sh --select packaging --verbose --accept-package-removals \
  --target-user "$TARGET_USER" >/tmp/tophat-changed.log 2>&1 ||
  fail 'run after the package change failed'
grep -q 'Package selection changed' /tmp/tophat-changed.log ||
  fail 'the marker ignored a changed package selection'
rpm -q "$EXTRA_PACKAGE" >/dev/null || fail "newly selected package ${EXTRA_PACKAGE} was not installed"

echo 'container-install.sh: PASS'
