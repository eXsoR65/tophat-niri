#!/bin/bash
# =============================================================================
#  proxmox-test.sh — snapshot-based install test on a Proxmox VM
#
#  STATUS: draft. It has been reviewed and dry-run, but never executed against
#  a real Proxmox host. Treat the first run as exploratory.
#
#  Run this ON the Proxmox host (it needs `qm`, and it must reach the guest over
#  SSH). The guest template must provide:
#    - cloud-init or a pre-created user with sudo, and an authorized SSH key
#    - qemu-guest-agent running (for IP discovery and reboot detection)
#    - a Fedora Minimal install matching the release under test
#
#  Required environment:
#    TEMPLATE_VMID   VMID of the Fedora Minimal template
#    GUEST_USER      non-root user with sudo on the guest
#  Optional:
#    VMID            new VM id (default: next free, via qm)
#    REPO_TARBALL    source archive to install (default: git archive of $REPO_REF)
#    REPO_DIR        git checkout to archive (default: current directory)
#    REPO_REF        git ref to test (default: dev)
#    VM_MEMORY       MB (default 4096), VM_CORES (default 2), VM_DISK (default 20G)
#    BRIDGE          (default vmbr0)
#    KEEP=1          leave the VM behind for inspection on failure
#    DRY_RUN=1       print the commands instead of running them
#
#  Usage:
#    TEMPLATE_VMID=9000 GUEST_USER=xavier DRY_RUN=1 ./proxmox-test.sh
# =============================================================================
set -euo pipefail

TEMPLATE_VMID="${TEMPLATE_VMID:?set TEMPLATE_VMID to the Fedora Minimal template}"
GUEST_USER="${GUEST_USER:?set GUEST_USER to the sudo-capable guest user}"
VMID="${VMID:-}"
REPO_DIR="${REPO_DIR:-$PWD}"
REPO_REF="${REPO_REF:-dev}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_CORES="${VM_CORES:-2}"
VM_DISK="${VM_DISK:-20G}"
BRIDGE="${BRIDGE:-vmbr0}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)

DRY_RUN="${DRY_RUN:-0}"
KEEP="${KEEP:-0}"
VM_PREEXISTING=0
REPO_TARBALL="${REPO_TARBALL:-}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# The remote command is expanded on this side on purpose.
# shellcheck disable=SC2029
guest_ssh() {
  ssh "${SSH_OPTS[@]}" "${GUEST_USER}@${GUEST_IP}" "$@"
}

guest_ip() {
  qm guest cmd "$VMID" network-get-interfaces 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for iface in data:
    if iface.get("name") == "lo":
        continue
    for addr in iface.get("ip-addresses", []):
        if addr.get("ip-address-type") == "ipv4" and not str(addr.get("ip-address", "")).startswith("127."):
            print(addr["ip-address"])
            sys.exit(0)
sys.exit(1)
'
}

wait_for_guest() {
  local deadline=$((SECONDS + 300))
  while ((SECONDS < deadline)); do
    if qm agent "$VMID" ping >/dev/null 2>&1; then
      GUEST_IP="$(guest_ip || true)"
      if [[ -n "${GUEST_IP:-}" ]]; then
        return 0
      fi
    fi
    sleep 5
  done
  die "guest did not become reachable within 5 minutes"
}

cleanup() {
  local status=$?
  if ((status != 0)) && [[ "$KEEP" == 1 ]]; then
    echo "Kept VM $VMID for inspection (KEEP=1)"
    return
  fi
  [[ -n "${VMID:-}" ]] || return 0
  # Only ever destroy a VM this run created. A caller-supplied VMID may name an
  # existing machine, and `qm destroy --purge` also removes its volumes.
  if [[ "$VM_PREEXISTING" == 1 ]]; then
    echo "Refusing to touch VM $VMID: it already existed before this run"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "[dry-run] would stop and destroy VM $VMID"
    return 0
  fi
  echo "Removing VM $VMID"
  qm stop "$VMID" --skiplock >/dev/null 2>&1 || true
  qm destroy "$VMID" --purge >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- source archive ---------------------------------------------------------
if [[ -z "$REPO_TARBALL" ]]; then
  REPO_TARBALL="$WORK_DIR/tophat-${REPO_REF}.tar.gz"
  echo "Archiving $REPO_DIR at $REPO_REF"
  git -C "$REPO_DIR" archive --format=tar.gz --prefix=tophat/ -o "$REPO_TARBALL" "$REPO_REF"
fi
[[ -f "$REPO_TARBALL" ]] || die "source archive not found: $REPO_TARBALL"

# --- create and boot --------------------------------------------------------
if [[ -z "$VMID" ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    VMID=9999
  else
    VMID="$(qm nextid)"
  fi
fi

if [[ "$DRY_RUN" != 1 ]] && qm status "$VMID" >/dev/null 2>&1; then
  VM_PREEXISTING=1
  echo "VM $VMID already exists; this run will not create or destroy it"
fi

echo "Cloning template $TEMPLATE_VMID -> VM $VMID"
run qm clone "$TEMPLATE_VMID" "$VMID" --name "tophat-it-$VMID" --full --storage local-lvm
run qm set "$VMID" --memory "$VM_MEMORY" --cores "$VM_CORES" --net0 "virtio,bridge=$BRIDGE"
run qm start "$VMID"

if [[ "$DRY_RUN" == 1 ]]; then
  GUEST_IP="192.0.2.10"
  echo '[dry-run] would wait for the guest agent to report an address'
else
  wait_for_guest
  echo "Guest reachable at $GUEST_IP"
fi

# --- install ----------------------------------------------------------------
run scp "${SSH_OPTS[@]}" "$REPO_TARBALL" "${GUEST_USER}@${GUEST_IP}:/tmp/tophat.tar.gz"
if [[ "$DRY_RUN" == 1 ]]; then
  echo '[dry-run] would unpack the archive to /opt/tophat on the guest'
else
  guest_ssh 'sudo mkdir -p /opt/tophat && sudo tar -xzf /tmp/tophat.tar.gz -C /opt/tophat --strip-components=1'
fi

if [[ "$DRY_RUN" == 1 ]]; then
  echo '[dry-run] would run: install.sh --verbose --accept-package-removals (over ssh)'
else
  guest_ssh "cd /opt/tophat && sudo ./install.sh --verbose --accept-package-removals --target-user $GUEST_USER | tee /tmp/tophat-install.log"
fi

# --- assertions -------------------------------------------------------------
if [[ "$DRY_RUN" == 1 ]]; then
  echo '[dry-run] would assert markers, greetd, greeter config and PAM over ssh'
else
  # shellcheck disable=SC2016 # expanded on the guest, not here
  guest_ssh '
  set -e
  test -f /var/lib/tophat/.completed
  for stage in preflight repos packaging config services finalize; do
    test -f "/var/lib/tophat/stage-$stage.done"
    test -f "/var/lib/tophat/stage-$stage.config"
  done
  systemctl is-enabled greetd.service
  grep -q "dms-greeter --command niri" /etc/greetd/config.toml
  grep -q "pam_gnome_keyring.so use_authtok" /etc/pam.d/greetd
  echo "post-install assertions: PASS"
'
fi

# --- reboot and re-verify ---------------------------------------------------
if [[ "$DRY_RUN" == 1 ]]; then
  echo '[dry-run] would reboot the guest and re-assert greetd + markers'
else
  # shellcheck disable=SC2029
  guest_ssh 'sudo systemctl reboot' || true
  sleep 20
  wait_for_guest
  # shellcheck disable=SC2016,SC2029 # this script runs on the guest
  guest_ssh '
    set -e
    systemctl is-enabled greetd.service
    test -f /var/lib/tophat/.completed
    echo "post-reboot assertions: PASS"
  '
fi

# --- idempotent rerun -------------------------------------------------------
if [[ "$DRY_RUN" == 1 ]]; then
  echo '[dry-run] would rerun the installer and require every stage to skip'
else
  guest_ssh "cd /opt/tophat && sudo ./install.sh --verbose --accept-package-removals --target-user $GUEST_USER" \
    >"$WORK_DIR/rerun.log" 2>&1 || die "rerun failed (see $WORK_DIR/rerun.log)"
  for stage in repos packaging config services; do
    grep -q "Skipped stage: $stage" "$WORK_DIR/rerun.log" || die "rerun re-ran stage $stage"
  done
  echo "idempotent rerun: PASS"
fi

echo "proxmox-test.sh: PASS (VM $VMID)"
