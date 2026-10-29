# Agent Reference — Tophat

Quick-start knowledge base for AI agents working in this repository. Read this
first; the README covers user-facing usage.

## Project identity

- **Name:** Tophat (version in `VERSION`, currently 2.7; last release: v2.7)
- **Purpose:** Opinionated installer that transforms a **Fedora Minimal**
  install into a **niri + DankMaterialShell (DMS)** workstation. Inspired by
  Omarchy's staged flow.
- **Language:** 100% Bash (`set -euo pipefail` everywhere). No build system.
- **License:** GPLv3.
- **Validation:** v2.7 validated end to end (2026-10-29) on the physical laptop
  with a real GPU — the accelerated-graphics path the retired Proxmox VM
  (llvmpipe, software rendering only) could never exercise. The run covered a
  full install from Fedora Minimal, an idempotent rerun that skipped every
  stage, clean lock acquire/release on both, and after rebooting a working
  graphical session: greetd login, niri, DankMaterialShell, installed
  applications, Wi-Fi and audio. v2.3 was the previous hardware-validated
  release; v2.4 was process-only, and v2.5–v2.7 shipped together in this run.
  Re-validate on hardware when a change touches installation, the greeter or the
  session path.
- **Upstream dependencies:** Fedora (dnf5), COPRs `yalter/niri`,
  `avengemedia/dms` (auto-pulls `avengemedia/danklinux`), `scottames/ghostty`,
  RPM Fusion free/nonfree, official Brave repo, greetd.

## Architecture

Single entry point `install.sh` orchestrates **7 stages**, executed in fixed
order:

```
preflight → repos → packaging → config → services → extras → finalize
```

Each stage is a directory `lib/<stage>/` whose `all.sh` **must** define a
`run_<stage>_stage()` function. `install.sh` sources the stage file then calls
that entry point by name — both must exist or the run aborts.

`lib/stages.sh` (sourced right after the path/color setup) holds the stage
registry, dependency resolver, and CLI parsing: `ALL_STAGES`,
`STAGE_DEPENDENCIES` (writable so tests can inject cycles),
`STAGE_WANTED`/`STAGE_RESOLVING`, `STAGES`, option defaults
(`DRY_RUN`/`FORCE`/`VERBOSE`/`ACCEPT_PACKAGE_REMOVALS`/`TARGET_USER`, all
exported there), `tophat_version()`, `usage()`, `parse_args`, `stage_exists`,
`stage_add_with_dependencies` (cycle-guarded), `resolve_stages`.
Definition-only — safe for the test suite to source.

`--version` prints `Tophat <version>` and exits 0 without touching the system;
it works as a plain user (no root check runs before `parse_args`). Version comes
from exported `TOPHAT_VERSION`, else `SETUP_ROOT/VERSION`, else `unknown`.

| Stage | Files | What it does |
|---|---|---|
| `preflight` | `detect_env.sh`, `detect_hardware.sh`, `system_update.sh` | Fedora/arch/network checks, resolves target user, GPU/Wi-Fi/form-factor detection, `dnf upgrade`, base utils |
| `repos` | `rpm_fusion.sh`, `brave.sh`, `copr.sh` | Enables RPM Fusion, Brave repo, COPRs; `dnf makecache` |
| `packaging` | `desktop_support.sh`, `hardware_firmware.sh`, `niri.sh`, `dms.sh`, `remove_replaced.sh`, `applications.sh` | Installs desktop stack (including `xdg-user-dirs`), niri, dms + dms-greeter, conditional Intel Wi-Fi firmware; removes DMS-replaced packages; optional user apps |
| `config` | `user_services.sh`, `dotfiles.sh` | Creates the target user's standard XDG directories and `~/.config` dirs, symlinks dms.service into `niri.service.wants/`; never runs `dms setup` (needs a graphical session — finalize summary tells the user to run it post-login); dotfiles is a stub |
| `services` | `all.sh` (self-contained) | graphical.target, writes `/etc/greetd/config.toml`, appends gnome-keyring PAM hooks to `/etc/pam.d/greetd`, enables greetd |
| `extras` | `flatpak.sh`, `distrobox.sh`, `homebrew.sh` | Opt-in only, gated by file presence in `packages/` |
| `finalize` | `all.sh` (self-contained) | dnf clean/autoremove, writes `/var/lib/tophat/.completed` marker; hard-guarded on earlier stage markers |

### Shared helpers (always loaded first)

- `lib/helpers/run_logged.sh` — `_log_write` core + `log`/`log_info`/`log_warn`/
  `log_error`/`log_ok`/`error_exit`; `run_logged <desc> <cmd...>` (logs, times,
  honors `DRY_RUN`/`VERBOSE`, exits on failure); stage tracking
  (`log_stage_start/complete`, `stage_already_run`, `skip_stage`); `log_summary`.
- `lib/helpers/checks.sh` — predicates (`cmd_missing`, `pkg_present`,
  `service_enabled`, ...); `read_list_file <file> <array>` (strips comments,
  dedupes, rejects control chars, never evals); `check_network_connectivity`;
  `resolve_target_user` (explicit arg → `$SUDO_USER`, never guesses; fails if
  root/nonexistent/no home).
- `lib/helpers/pkg.sh` — `pkg_install` (skips installed), `pkg_install_from_list`,
  `pkg_remove` (interactive confirm unless `--accept-package-removals`; writes
  removed-manifest to state dir), `pkg_remove_from_list`, `enable_copr`,
  `repo_enable_rpm_fusion`, `enable_service`, and the sanitized privilege-drop
  pair `target_user_command` / `run_as_target_user` (`runuser` + `env -i`
  allowlist env, passes through only proxy vars).

### Key environment contract

`install.sh` exports: `SETUP_ROOT`, `SETUP_LIB`, `SETUP_PACKAGES`,
`SETUP_LOG_DIR`, `SETUP_LOG`, `SETUP_STATE_DIR`, `DRY_RUN`, `FORCE`, `VERBOSE`,
`ACCEPT_PACKAGE_REMOVALS`, `TARGET_USER`, `TOPHAT_VERSION`, `NIRI_COPR`,
`DMS_COPR`, `GHOSTTY_COPR`, `CLR_*` colors. Preflight additionally exports
`FEDORA_VERSION`, `ARCHITECTURE`, `NETWORK_OK`, `GPU_VENDOR`, `FORM_FACTOR`,
`HAS_INTEL_WIFI`, `INTEL_WIFI_DETECTION_RELIABLE`, `TARGET_USER_HOME`.

## Conventions & invariants

1. **Idempotency**: every stage except preflight checks `stage_already_run`;
   markers live at `$SETUP_STATE_DIR/stage-<stage>.done`. `skip_stage` marks a
   stage skipped *without* writing a marker (used by extras so later opt-in
   files are discovered). `--force` bypasses markers.

   Markers record *what* was completed: `completed=`, `version=`, `user=`, plus
   a verbatim snapshot of the package lists in `stage-<stage>.config`
   (`_tophat_config_snapshot`). A marker is honoured only when the version, the
   target user and the package selection all still match; otherwise the stage
   re-runs with a logged reason. The snapshot is compared as text because
   `sha256sum`/`cksum` are not guaranteed on Fedora Minimal.
2. **Dry run**: `run_logged` prints the command and returns 0. File writes must
   be manually gated with `[[ "$DRY_RUN" != true ]]`. Dry-run logs go to
   `${TMPDIR:-/tmp}`, not `/var/log/tophat`.
3. **Stage dependencies**: `STAGE_DEPENDENCIES` assoc array in
   `lib/stages.sh`; `--select` recursively pulls dependencies; cycles fail
   loudly (visited-set guard in `stage_add_with_dependencies`).
4. **Package lists**: one entry per line in `packages/*.packages`; `#` comment,
   blanks ignored. User-local copies (`applications.packages`, etc.) are
   gitignored — only `.template` files are committed.
5. **Never eval list contents.** Validate extras input: Flatpak IDs and brew
   formulae are regex-checked before use.
6. **User context**: never run user-level things as root — use
   `run_as_target_user` / `target_user_command`. Never capture such calls via
   `$(...)`: a spawned grandchild inheriting stdout holds the pipe open and
   hangs the caller — redirect to a file with stdin detached instead.
7. **Destructive actions** require `--accept-package-removals` or a TTY
   confirmation: `pkg_remove` for the replacement list, and `finalize`'s
   `dnf autoremove` (which can remove more than that list, since it removes
   whatever the solver calls unneeded). Without consent the autoremove is
   skipped, with a message telling the user to run it themselves.
8. **Logs/state**: live runs write `/var/log/tophat/runs/<timestamp>.log`
   (0640) with `latest.log` symlink, and state under `/var/lib/tophat/`.
9. **One run at a time**: `acquire_run_lock` takes `$SETUP_STATE_DIR/.lock.d`
   with an atomic `mkdir` and records its pid. Exactly one mechanism, on
   purpose: two backends cannot exclude each other — a run that starts before
   util-linux is installed would hold a directory lock while a later run, now
   seeing `flock`, takes a different lock file, and both proceed. `mkdir` is
   atomic, needs nothing beyond the shell, and exists before any package is
   installed.
   The lock is never reclaimed automatically, because reclaiming races with
   acquiring; a stale directory is reported with the exact command to remove it
   (`rm -rf .lock.d`). Dry runs take no lock.

10. **Exit cleanup is registered, never trapped**: anything needing cleanup uses
    `register_exit_handler <function>` (`lib/helpers/run_logged.sh`), which
    composes handlers behind one EXIT trap. A bare `trap ... EXIT` replaces the
    dispatcher and silently drops every other handler — Homebrew's temp-file
    cleanup did that and left the lock behind after a successful install.
    `locking_test.sh` fails if a bare EXIT trap reappears outside
    `run_logged.sh`.

## Known quirks / rough edges

- `hardware_firmware.sh` re-detects Intel Wi-Fi only when
  `INTEL_WIFI_DETECTION_RELIABLE` is not true — i.e., preflight ran without
  `lspci` (minimal install before pciutils) or preflight never ran.
- `dotfiles.sh` is an intentional stub.
- `wget` is deliberately not installed: Fedora 44+ has no package by that name
  (it split into `wget1`/`wget2` with `-wget` subpackages that provide the
  binary, so `dnf install wget` depended on provides resolution with two
  candidates). `curl` covers downloads and Tophat itself never calls `wget`.
- `preflight` refuses to run off Fedora: `require_fedora` checks
  `ID=fedora` in `/etc/os-release` *before* the first `rpm` call, so a
  non-Fedora host gets a clear message instead of `rpm: command not found`.
  It takes an explicit path, which is how the test exercises it.
- `services` writes `/etc/greetd/config.toml` only when it differs, backs a
  differing file up to `<path>.tophat-backup.<timestamp>`, and installs it with
  a same-directory `mktemp` + `mv` so a partial write can never leave the
  machine without a greeter. `/etc/pam.d/greetd` is backed up the same way, and
  each gnome-keyring hook (auth/session/password) is verified individually — a
  file can mention `pam_gnome_keyring.so` on one line and still not auto-start
  the keyring.
- `config` chowns only the paths it creates (the three `~/.config` subtrees),
  not `~/.config` recursively.
- `--select finalize` refuses to run (and won't write `.completed`) while any
  of preflight/repos/packaging/config/services markers are missing. `--force`
  does **not** bypass this: a false `.completed` marker would mislead every
  later run, so force only re-runs stages (D2.3, revised in v2.6).

## Planned work

- **TUI** (OpenTUI + `@opentui/react`, Bun): plan lives in
  `docs/TUI-PLAN.md`. In-repo `tui/`, `./tophat` launcher with Bash fallback,
  milestones M1–M5. Not yet implemented — Bash remains the only engine.
- **v2.4–v2.7 hardening** is done: every stage has at least one test and the
  review findings are closed or explicitly deferred, and v2.7 is hardware
  validated. What remains — the dotfiles decision, community files, the `dev`
  branch question (Phase 6) and the Fedora 45 GA re-check (8.5) — is tracked in
  `docs/TODO.md`.

## Validation & CI

CI (`.github/workflows/ci.yml`, runs on push to main/dev and PRs) enforces, in
order:

```bash
find . -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n && bash -n install.sh
shellcheck -s bash -x -e SC1090,SC1091 install.sh $(find lib tests kickstart -name '*.sh' | sort)
shfmt -d -i 2 -ci install.sh lib tests kickstart   # 2-space indent, case-indent
kickstart/validate-kickstart.sh                    # rejects unsafe ks defaults
for t in tests/*_test.sh; do "$t"; done             # 16 files: helpers, pkg, arg_parse,
                                                     # stage_resolution, finalize_guard, locking,
                                                     # lock_concurrency, marker_invalidation,
                                                     # failure_recovery, exit_handler_scope,
                                                     # and one per stage (config, preflight,
                                                     # repos, packaging, services, extras)
```

The `shell` job also asserts that `VERSION` matches the version in the
`install.sh` header, which nothing else checks.

Inside the Fedora containers the job additionally walks **all seven stages** as
a `./install.sh --dry-run` against a throwaway user, which is the closest CI can
get to a real install without a VM. `docs/INTEGRATION-TESTING.md` records what
still needs a VM or a real GPU, and the manual procedure for both.

Two jobs: `shell` on `ubuntu-latest` runs all five gates above. `fedora` runs
inside a container matrix of `fedora:latest` (the current release) and
`fedora:45` (the next one), covering only what genuinely needs Fedora — bash
syntax, the kickstart validator, the test suite, `./install.sh --version` /
`--help` smoke tests, and two release-readiness checks:

- every package Tophat installs from Fedora's own repositories resolves on that
  release (`dnf repoquery`; COPR-provided packages are excluded)
- RPM Fusion's release RPMs and the four COPR chroots (niri, dms, danklinux,
  ghostty) exist for that release

Those two catch the failure modes our own code cannot fix: a renamed or retired
package name, or an upstream repository with no tree for the new release. Lint
and format stay on Ubuntu: depending on Fedora's ShellCheck/shfmt packaging
makes a gate fail for reasons unrelated to whether the installer works. The fedora job pulls the image in its own step and
re-emits a failed container's output tail as a single annotation, because
container stdout is otherwise invisible to tooling (GitHub also caps annotations
at ~10 per step).

Releases: push an annotated tag `v<version>` matching `VERSION`;
`.github/workflows/release.yml` re-runs the gates, fails on a VERSION/tag
mismatch, then publishes a source archive + `SHA256SUMS` and opens the release
with the tag annotation as its body. The archive is reproducible: `git archive`
to tar, `gzip -n`, and the workflow rebuilds it once to compare digests. Never
create releases by hand.

Run `tests/verify_all.sh` before pushing: it runs all five gates, the whole
suite, and the lock concurrency stress (the races the lock guards against only
appear when processes interleave, which a sequential suite cannot produce).
`FAST=1` skips the stress rounds while iterating.

**Run all five before considering a change done.** Style: shfmt `-i 2 -ci`,
ShellCheck-clean (SC1090/SC1091 exempt for dynamic sourcing), shellcheck
`source=` directives used where paths are static.

## Rules of engagement for agents

- Changes must remain root-safe, idempotent, dry-run-aware, and non-interactive
  by default.
- New stage = new `lib/<stage>/all.sh` with `run_<stage>_stage()` + entry in
  `ALL_STAGES` and `STAGE_DEPENDENCIES` + README updates.
- Keep the kickstart example placeholder-driven and safe; the validator must
  keep passing.
- Bump `VERSION` (and the `install.sh` header comment) when behavior changes
  meaningfully.
- Never commit user-local package selections (gitignored).
- Test additions go in `tests/` as standalone bash scripts mirroring
  `helpers_test.sh` style.
