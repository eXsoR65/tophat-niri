# Integration testing

What is automated, what is not, and the manual procedure for the gap. Written so
the limits are explicit rather than implied by a green check mark.

## What CI proves

| Layer | Where | What it actually verifies |
|---|---|---|
| Behaviour tests | `tests/*_test.sh`, on Ubuntu and inside `fedora:latest` + `fedora:45` | Stage logic, package handling, argument parsing, marker invalidation, locking, failure handling. System commands are stubbed through `PATH`; no root, no dnf transactions |
| Full dry run | `fedora:latest` + `fedora:45` containers | All seven stages are walked end to end on a real Fedora userspace: package lists parsed, target user resolved, greeter/PAM/autoremove paths taken without changes. Catches missing commands and bad assumptions |
| Package availability | same containers | Every package we install from Fedora repos resolves on that release, and RPM Fusion plus the four COPR chroots publish a tree for it |
| Release artifacts | `release.yml` | Tag matches `VERSION`, gates pass, archive is byte-for-byte reproducible, `SHA256SUMS` published |

## What CI cannot prove

GitHub-hosted runners cannot run a booted Fedora system with systemd, real dnf
transactions and a GPU. These therefore require a VM or hardware:

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
