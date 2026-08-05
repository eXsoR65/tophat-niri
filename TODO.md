# TODO — Tophat Improvement Plan

Derived from the codebase review (see `.agent.md`). Items are grouped into
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

## Suggested commit order

1. Phase 1 (single commit)
2. Phase 2 items 2.1 → 2.5 (one commit each)
3. Phase 3: 3.0 refactor first, then tests + CI wiring
4. Phase 4 docs + VERSION bump
