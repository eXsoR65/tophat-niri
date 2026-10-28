# TODO — Tophat Improvement Plan

Derived from the codebase review (see `AGENTS.md`). Items are grouped into
phases; each phase should land with all CI gates green:

```bash
find . -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n && bash -n install.sh
shellcheck -s bash -x -e SC1090,SC1091 install.sh $(find lib tests kickstart -name '*.sh' | sort)
shfmt -d -i 2 -ci install.sh lib tests kickstart
kickstart/validate-kickstart.sh
for t in tests/*_test.sh; do "$t"; done
```

## Design decisions (locked in)

- **D2.5 (superseded):** `dms setup` was first moved to
  `target_user_command`, then removed entirely — it requires a graphical
  session and never worked from the installer. Post-login message in
  `finalize` + README covers it.
- **D2.3:** Finalize stage gets a **hard guard**, not a dependency change:
  when finalize runs and any earlier stage marker is missing, it exits with an
  error listing the missing stages unless `--force` is given. Rationale:
  depends-on-all would turn a selective finalize into a full install; a hard
  guard matches Tophat's fail-rather-than-guess philosophy and keeps
  `dnf autoremove` from running on partial installs.

---

## Phase 1 — Quick wins (low risk, cosmetic/hygiene)

- [x] **1.1** Remove dead `SETUP_FILES` export (no `files/` dir exists) — `install.sh`
- [x] **1.2** Remove leftover conversation comments ("NEW per your request",
      "as you requested") — `lib/helpers/pkg.sh`, `lib/repos/rpm_fusion.sh`
- [x] **1.3** Fix typos: "evolutioning" → "evolving" (`README.md`),
      "Brave Orgin" → "Brave Origin" (`packages/applications.packages.template`),
      "Required packaged for must functions" header (`lib/packaging/desktop_support.sh`)
- [x] **1.4** Drop deprecated `fastestmirror=True` from the dnf.conf snippet —
      `kickstart/tophat-minimal.ks.example`
- [x] **1.5** Verify the "DMS 1.2 or newer" note in
      `packages/dms-companions.packages` is still accurate ✔ accurate (DMS latest v1.5.3)

## Phase 2 — Correctness & robustness (behavioral)

- [x] **2.1** Make the banner version-agnostic: compute padding from
      `TOPHAT_VERSION` length instead of hardcoded spaces — `install.sh`
- [x] **2.2** Add a visited-set cycle guard to `stage_add_with_dependencies` —
      `install.sh` (later moved to `lib/stages.sh` in Phase 3)
- [x] **2.3** Finalize hard guard per **D2.3**: verify all earlier stage
      markers exist before running; error out listing missing stages unless
      `--force` — `lib/finalize/all.sh`
- [x] **2.4** Deduplicate Intel Wi-Fi detection: add a reliability flag set by
      preflight when `lspci` was available; `hardware_firmware.sh` re-detects
      only when the earlier check was unreliable —
      `lib/preflight/detect_hardware.sh`, `lib/packaging/hardware_firmware.sh`
- [x] **2.5** Replace `su - "$TARGET_USER" -c "dms setup"` with
      `target_user_command` per **D2.5**, keeping timeout + graceful
      degradation — `lib/config/user_services.sh`
      *(superseded: invocation removed entirely, see D2.5)*

## Phase 3 — Test coverage (biggest gap)

- [x] **3.0** Extract stage resolution + argument parsing from `install.sh`
      into a sourceable `lib/stages.sh`; `install.sh` becomes a thin caller
      (enables 3.1/3.3 without executing the installer)
- [x] **3.1** `tests/stage_resolution_test.sh` — `--select` pulls dependencies
      in canonical order; invalid/empty stage names fail; cycle guard (2.2)
      terminates
- [x] **3.2** `tests/pkg_test.sh` — `pkg_install` skips installed packages;
      `pkg_remove` refuses without confirmation, honors
      `ACCEPT_PACKAGE_REMOVALS` (mock `rpm`/`dnf` via PATH stubs)
- [x] **3.3** `tests/arg_parse_test.sh` — `--select`/`--target-user` reject
      missing and `--`-prefixed values; unknown options fail
- [x] **3.4** `tests/finalize_guard_test.sh` — D2.3 behavior: refuses without
      markers, lists missing stages, proceeds with `--force`
- [x] **3.5** CI "Tests" step runs all `tests/*_test.sh` in a loop —
      `.github/workflows/ci.yml`

## Phase 4 — Documentation & process (polish)

- [x] **4.1** Add "Local development" section to README covering the 5 CI
      gates and installing `shellcheck`/`shfmt` on Fedora
- [x] **4.2** Bump `VERSION` 2.1 → 2.2 after Phases 1–2 land; sync the
      `install.sh` header comment
- [x] **4.3** (Optional) Rename `assets/*transperant*` → `*transparent*` with
      README refs updated ✔ done (files, SVG titles, README refs)
- [x] **4.4** Decide the fate of the `dotfiles.sh` stub ✔ **keep as documented
      stub** — no spec exists for repo URL or linking strategy; an
      extras-style opt-in would be guesswork without requirements

## Phase 5 — v2.4 hardening (process, not installer behavior)

The goal of this phase is to make the project's *process* as solid as its code:
v2.3 was merged and released by hand, and one release step needed credentials
that only existed in a browser. Nothing here changes what the installer does on
a target machine except the new `--version` flag.

- [x] **5.1** `--version` flag: `tophat_version()` in `lib/stages.sh` (exported
      `TOPHAT_VERSION` → `VERSION` → `unknown`), documented in `usage()`, the
      README and `tests/arg_parse_test.sh`. Works without root.
- [x] **5.2** Tag-triggered release workflow (`.github/workflows/release.yml`):
      re-runs all five gates, refuses to publish when `VERSION` disagrees with
      the tag, builds a source archive + `SHA256SUMS`, and creates or refreshes
      the release with `gh` (annotated tag body as the notes).
- [x] **5.3** Fedora CI job: the Fedora-relevant gates inside `fedora:latest`
      (bash syntax, kickstart validator, test suite, `--version`/`--help` smoke
      tests), so dnf5/Fedora paths are exercised instead of only Ubuntu. Lint
      and format stay on Ubuntu — Fedora ShellCheck/shfmt packaging is not
      something a gate should depend on.
- [x] **5.4** Correct the TUI plan: the replacement list is
      `packages/remove-replaced.packages`, not `packages/*.replaced`.
- [x] **5.5** `dev` fast-forwarded to `main` after the v2.3 release, so the
      integration branch is no longer stale.

## Phase 6 — Backlog

- [x] **6.1** Stage-level tests for the five stages that had none:
      `preflight` (distro guard + hardware detection), `repos` (all repositories,
      single `makecache`, marker skip), `packaging` (Intel Wi-Fi conditional, DMS,
      optional apps, marker skip), `services` (greeter backup/idempotency,
      missing dms-greeter refusal), `extras` (skip without opt-ins, input
      validation, distrobox resolution). Eleven test files now.
- [ ] **6.2** Decide the fate of the `dotfiles.sh` stub (deferred from 4.4):
      implement behind an opt-in file, or delete it.
- [ ] **6.3** Community files: `CONTRIBUTING.md`, issue templates,
      `SECURITY.md`. The repo has stars and a fork but no contribution path.
- [ ] **6.4** Decide whether `dev` stays a long-lived integration branch now
      that releases are tag-driven and CI runs on pull requests.
- [ ] **6.5** Release assets beyond the source archive (e.g. a TUI binary from
      TUI-PLAN M4) once that work exists.

### From the v2.4 repository review

- [x] **6.6** Fail *clearly* on non-Fedora hosts: `require_fedora` checks
      `ID=fedora` in `/etc/os-release` before the first `rpm` call and names the
      detected system. Takes an explicit path so the guard is testable.
- [x] **6.7** `services` no longer clobbers `/etc/greetd/config.toml`: it writes
      only when the content differs and backs the old file up to
      `.tophat-backup.<timestamp>` first.
- [x] **6.8** `config` chowns only the paths it creates (the three `~/.config`
      subtrees plus their parents) instead of `~/.config` recursively, and uses
      the user's primary group rather than assuming group == username.
- [x] **6.9** *Not a defect.* `packages/intel-wifi.packages` already lists
      `iwlwifi-dvm-firmware`, `iwlwifi-mld-firmware` **and** `iwlwifi-mvm-firmware`.
      The earlier finding came from reviewing truncated `head -80` output. The
      new packaging test now asserts the firmware set is installed when Intel
      Wi-Fi is detected and skipped when it is not.
- [x] **6.10** CI now asserts that `VERSION` matches the version in the
      `install.sh` header (new `Version consistency` step in the `shell` job).

## Phase 7 — v2.5 review fixes (low severity, all landed)

- [x] **7.1** Removed four unreferenced asset files (two PNGs, two SVGs); the
      release archive drops from ~6.8 MB to ~1.5 MB. They remain in git history:
      `git checkout 0a98a7c -- <path>` restores any of them.
- [x] **7.2** `pkg_install` declares its loop variable `local` (it was leaking
      `pkg` into the global scope).
- [x] **7.3** `check_network_connectivity` passes the host to the TCP probe as a
      positional argument and rejects anything that is not a hostname/IP, so a
      host can never be evaluated as shell code.
- [x] **7.4** One `dnf makecache` per repos stage (it ran twice, before the COPRs
      existed and again after).
- [x] **7.5** A missing `applications.packages` logs one informational line
      instead of two warnings on every run.
- [x] **7.6** `finalize` records `user=unknown` rather than `user=x` when no target
      user was ever resolved.
- [x] **7.7** `homebrew.sh`'s temporary installer file: the `EXIT` trap is the
      only one in the script and is cleared on the success path, so it is left as
      is and documented here rather than replaced.

## Phase 8 — Fedora 45 readiness (verified 2026-10-27)

Fedora 45 was still pre-GA when this was checked (no `releases/45` tree on the
mirrors yet; only `development/45`), so everything below is verified against the
branched tree and a real `fedora:45` container, not a released Fedora.

- [x] **8.1** Code runs on Fedora 45: all 11 tests, the kickstart validator and
      the `--version`/`--help` smoke tests pass inside `fedora:45`.
- [x] **8.2** Every package Tophat installs from Fedora's own repositories
      resolves on F45 (48 packages). `wget` was the only casualty — the package
      name is gone in 44 and 45, so it is no longer installed.
- [x] **8.3** Upstream repositories publish F45: RPM Fusion free/nonfree
      `-release-45` RPMs exist, and niri/dms/danklinux/ghostty all have
      `fedora-45` chroots (x86_64 and aarch64).
- [x] **8.4** CI now runs the Fedora job as a matrix over `fedora:latest` and
      `fedora:45` and enforces both checks above, so the next release is tested
      before it ships rather than after.
- [ ] **8.5** Re-run the Fedora job once F45 is actually GA: RPM Fusion swaps
      its release RPMs from `development/45` to `releases/45` at GA, and that
      path is the one real installs will use.
- [ ] **8.6** Live validation of v2.5 (and F45) on the laptop, since v2.5
      changes installer behaviour.

## Phase 9 — Installation safety (review Phase A)

From the 2026-10-28 repository review. The theme is installing/rerunning safety,
not new features.

- [x] **9.1** `--select` validation: an empty value used to mean "no selection",
      i.e. install everything. Empty, leading/trailing and doubled commas are now
      rejected, with the stage list echoed back.
- [x] **9.2** `dnf autoremove` in `finalize` is opt-in: it previews the
      transaction (`--assumeno`), then removes only with
      `--accept-package-removals` or a TTY confirmation. Otherwise it is skipped
      with guidance.
- [x] **9.3** `finalize`'s prerequisite guard is no longer bypassable with
      `--force` — force re-runs stages, it does not let an incomplete install be
      marked complete.
- [x] **9.4** Greeter config is written atomically (same-directory temp file +
      rename) after its backup, and `/etc/pam.d/greetd` is backed up before
      modification with every gnome-keyring hook verified individually.
- [x] **9.5** Release workflow: `contents: write` is scoped to the publishing
      job; the verify job runs with `contents: read`.
- [x] **9.6** README release example derives the tag from `VERSION`, so it can no
      longer go stale (it said v2.4 while the source said 2.5).
- [ ] **9.7** *Needs repository admin, not code:* protect `main` — require the
      `shell` and `fedora` checks, block force-pushes, require a PR for changes.
      Both branches report `protected: false` today.
- [ ] **9.8** Pin workflow actions to reviewed commit SHAs once Dependabot is
      keeping them current.

## Phase 10 — Reliability and test infrastructure (review Phases B/C)

- [x] **10.1** Configuration-aware markers: each marker stores version, target
      user and a snapshot of the package lists; any change re-runs that stage
      with a logged reason (`tests/marker_invalidation_test.sh`).
- [x] **10.2** Concurrent runs: atomic `mkdir` lock with a pid file and stale
      lock breaking; dry runs are exempt (`tests/locking_test.sh`).
- [x] **10.3** Interruption and failure tests: a failed or interrupted stage
      never writes a marker, so a rerun resumes instead of skipping
      (`tests/failure_recovery_test.sh`).
- [x] **10.4** Failure recovery hint: the error trap says completed stages are
      recorded and points at `--force` for re-running them.
- [x] **10.5** Full dry-run install in CI: all seven stages walked on
      `fedora:latest` and `fedora:45` against a throwaway user.
- [x] **10.6** Reproducible release archive: `git archive` + `gzip -n`, rebuilt
      in-workflow and digest-compared before upload.
- [x] **10.7** `docs/INTEGRATION-TESTING.md` states exactly what CI proves and
      what needs a VM or GPU, with the manual procedure for each.
- [x] **10.8a** Automated harness written: `.github/workflows/integration.yml`
      (dispatched real install in a systemd container) and
      `tests/integration/container-install.sh`, plus a drafted
      `tests/integration/proxmox-test.sh` for VM-level runs.
- [ ] **10.8b** Run the integration workflow once and fix whatever it finds.
- [ ] **10.8c** Run the VM scenarios in `docs/INTEGRATION-TESTING.md` (fresh
      install, rerun, interrupted run, upgrade) on a Fedora Minimal VM.
- [ ] **10.9** Run the real-GPU checklist on the laptop (also covers 8.6).

## Suggested commit order

1. Phase 1 (single commit)
2. Phase 2 items 2.1 → 2.5 (one commit each)
3. Phase 3: 3.0 refactor first, then tests + CI wiring
4. Phase 4 docs + VERSION bump
