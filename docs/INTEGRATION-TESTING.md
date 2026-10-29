# Integration testing

What is automated, what is not, and the manual procedure for the gap. Written so
the limits are explicit rather than implied by a green check mark.

## Tiers

| Tier | Trigger | Runs | Proves |
|---|---|---|---|
| 0 — fast | every push / PR | `tests/*_test.sh`, full dry run, package + upstream-repo checks (`.github/workflows/ci.yml`) | logic, CLI, markers, locking, stage wiring on a real Fedora userspace |
| 1 — real install | **manual** (any Fedora release), **weekly** (Mon 05:00 UTC), and on every `v*` tag (`.github/workflows/integration.yml`) | `tests/integration/container-install.sh` in a privileged systemd container | real dnf transactions, RPM Fusion + COPRs resolving, greetd enablement, PAM edits, marker contents, idempotent rerun, marker invalidation |
| 2 — VM | manual, on the Proxmox host | `tests/integration/proxmox-test.sh` (draft) | everything above plus **reboot** behaviour, on a real Fedora Minimal install |
| 3 — hardware | manual | this document | GPU path, graphical login, niri/DMS session |

Tier 1 never runs on every push: it pulls the whole desktop stack (several GB,
10–20 min). It runs weekly as a drift alarm (a renamed package or a lagging COPR
fails before a user hits it), on every `v*` tag against the code being released,
and on demand for any Fedora release — including the next one before it is GA.

Tier 2 is a draft: reviewed and dry-run (`DRY_RUN=1 ./proxmox-test.sh`) but not
yet executed against a real Proxmox host. It needs a Fedora Minimal template
with `qemu-guest-agent`, an SSH key for the guest user, and sudo.

```bash
# Tier 1: click Run workflow, or from a machine with gh authenticated:
gh workflow run integration -f container=fedora:45

# Tier 2, on the Proxmox host:
TEMPLATE_VMID=9000 GUEST_USER=xavier DRY_RUN=1 ./tests/integration/proxmox-test.sh   # preview
TEMPLATE_VMID=9000 GUEST_USER=xavier ./tests/integration/proxmox-test.sh             # real
```

## What CI proves

| Layer | Where | What it actually verifies |
|---|---|---|
| Behaviour tests | `tests/*_test.sh`, on Ubuntu and inside `fedora:latest` + `fedora:45` | Stage logic, package handling, argument parsing, marker invalidation, locking, failure handling. System commands are stubbed through `PATH`; no root, no dnf transactions |
| Full dry run | `fedora:latest` + `fedora:45` containers | All seven stages are walked end to end on a real Fedora userspace: package lists parsed, target user resolved, greeter/PAM/autoremove paths taken without changes. Catches missing commands and bad assumptions |
| Package availability | same containers | Every package we install from Fedora repos resolves on that release, and RPM Fusion plus the four COPR chroots publish a tree for it |
| Release artifacts | `release.yml` | Tag matches `VERSION`, gates pass, archive is byte-for-byte reproducible, `SHA256SUMS` published |

## What even Tier 1 cannot prove

Tier 1 has real systemd and real dnf, but no firmware, no DRM and no reboot.
These therefore require a VM (Tier 2) or hardware (Tier 3):

- a real fresh install (actual package installation, greetd enablement, PAM)
- rerun/idempotency against real markers and real `dnf`
- upgrade behaviour between releases
- graphical login, niri startup, DMS initialisation (needs a real GPU; a
  software-rendered VM exercises llvmpipe, not the driver path)

## Manual procedure — Fedora Minimal VM

Take a snapshot before each scenario so every run starts from the same state.

1. **Fresh install.** Fedora Minimal (current release), non-root user with
   sudo, network up.
   ```bash
   git clone https://github.com/eXsoR65/tophat-niri.git
   cd tophat-niri
   sudo ./install.sh --verbose
   ```
   Expect: all seven stages complete, `/var/lib/tophat/stage-*.done` present for
   preflight/repos/packaging/config/services/finalize, `/var/lib/tophat/.completed`
   written, `/etc/greetd/config.toml` present, `systemctl is-enabled greetd`
   enabled. Reboot and log in.
2. **Rerun (idempotency).** `sudo ./install.sh --verbose` again. Expect every
   stage skipped, no package work, no greeter rewrite (config already current).
3. **Changed selection invalidates markers.** Add a package to
   `packages/applications.packages`, rerun. Expect the packaging stage to re-run
   and say the package selection changed.
4. **Interruption.** Start an install and Ctrl-C during packaging. Expect no
   marker for the interrupted stage; rerunning resumes from it and does not
   redo completed stages.
5. **Upgrade.** Install release N, then check out release N+1 and rerun. Expect
   stages whose configuration changed to rerun once (the marker records the
   version).
6. **Failure path.** Temporarily break a COPR URL, run: expect a clear failure,
   no marker for that stage, and a rerun after fixing it to succeed.

Roll back by restoring the snapshot. Do not "repair" a VM between scenarios —
that is what the snapshots are for.

## Manual procedure — real GPU

On the physical laptop, from a fresh Fedora install:

- graphical login via greetd/DMS greeter appears
- niri starts; `niri msg version` responds
- DMS shell renders with the expected theme; `dms run` is *not* started from
  niri config (the systemd user service owns it)
- audio works (PipeWire), Wi-Fi works if the machine has Intel Wi-Fi
- `dms setup` and `dms greeter sync` run once after first login
- reboot returns to the greeter without manual intervention
