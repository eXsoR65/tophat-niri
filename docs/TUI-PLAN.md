# Tophat TUI Plan

Status: **M1–M3 implemented** (M4–M5 planned)
Frontend stack: [OpenTUI](https://opentui.com) + React bindings + Bun
Tracking: this document (not `docs/TODO.md` — Phases 1–4 there are done)

## Context

Tophat is a zero-dependency Bash installer (bash + dnf only) targeting fresh
Fedora minimal installs. A TUI would improve its weakest moments: discoverable
stage selection, visible progress, and the two interactive prompts (package
removals, reboot). OpenTUI is a Zig-core terminal UI library with TypeScript
bindings (`@opentui/react`), used in production by opencode.

The core tension: OpenTUI needs Bun/Node, which a fresh Fedora install does not
have. Therefore the TUI is **strictly additive** — if it is missing, broken,
declined, or the terminal is non-interactive, `./install.sh` works exactly as
it does today.

## Decisions

- **D-T1**: TUI lives **in-repo** under `tui/` (monorepo). The Bash engine
  remains independently runnable and installable; CI gates for Bash are
  unaffected.
- **D-T2**: **`@opentui/react`** bindings. Most examples/docs, lowest learning
  curve; five simple screens do not need Solid's reactivity or the raw core's
  boilerplate. Revisit only if we hit real limitations.
- **D-T3**: Entry point is **`./tophat`**, a thin Bash launcher: if a TUI
  binary is available (built locally or fetched from Releases) and the terminal
  is interactive, it runs the TUI; otherwise it `exec`s `install.sh "$@"`
  unchanged. A `--no-tui` flag forces the fallback.
- **D-T4**: **Simple v1** (M1): configure → run → watch log → done. Rich stage
  visualization and structured events come later.

## Architecture

Bash stays the engine. The TUI configures, launches, and observes it — it never
reimplements Tophat logic:

```
┌─────────────┐   flags/answers    ┌──────────────────┐
│ TUI (bun)   │ ─────────────────► │ install.sh       │
│ OpenTUI     │ ◄───────────────── │ stages, helpers  │
└─────────────┘  log + state dir   └──────────────────┘
```

Phase 2/3 work already solves the TUI's hardest problems:

- Stage resolution is single-sourced in `lib/stages.sh` — the TUI shells out
  for the resolved plan instead of reimplementing it.
- The finalize guard + stage markers make partial runs resumable for free.
- `pkg_remove` already accepts `--accept-package-removals` upfront, so the TUI
  collects that answer on the config screen — no mid-run IPC.
- `run_logged` already writes everything to `$SETUP_LOG`; the state dir
  already gets `stage-*.done` markers. M1 reads both — **no Bash changes for
  progress display**.

### Required Bash changes (small, staged)

| Milestone | Change | Size |
|---|---|---|
| M1 | `TOPHAT_TUI=1` guard. Both prompts are already `[[ -t 0 ]]`-gated and the TUI spawns with stdin from `/dev/null`, so they cannot block; the guard adds one behaviour — declining removals in the TUI skips them instead of failing the stage. | ~8 lines |
| M3 | When `TOPHAT_TUI=1`, `run_logged`/`run_stage` additionally emit NDJSON events to `$SETUP_STATE_DIR/events.ndjson`: `stage_start`, `stage_done`, `stage_fail`, `command`, `marker` | ~30 lines |

The TUI also **passes stdin from `/dev/null`** to the installer so nothing can
block on input even if a prompt slips through.

## Scaffold provenance

`tui/` was regenerated from `bunx create-tui@latest -t react` on 2026-10-30, so
the config files are the generator's rather than hand-written. Two deliberate
deviations, both recorded here because re-running the generator would undo them:

- **`types: ["bun"]` added to `tsconfig.json`.** The template's demo imports
  neither Node builtins nor `bun:test`, so it omits the field; this project uses
  `node:fs`, `node:child_process` and `bun:test`.
- **Dependencies stay on the installed versions** (`@opentui/*` 0.8.0,
  React 19.3) rather than the template's pinned 0.7.0. The generator lags the
  library, and the tests target 0.8.0.

Everything else is the template: `module: Preserve`, `moduleDetection: force`,
`verbatimModuleSyntax`, `noUncheckedIndexedAccess`, `noFallthroughCasesInSwitch`,
`noImplicitOverride`, a project-local `.gitignore`, the `dev`/`typecheck`
scripts and `engines.bun`. The stricter flags found no defects — the row lookup
was already guarded — but they will catch new ones.

## Milestones

- [x] **M1 — Scaffold + simple flow.** Done 2026-10-30. `tui/` Bun project with
  `@opentui/react`. Screens: Config (target-user, stage multi-select, dry-run /
  verbose / accept-removals toggles) → Run (live `$SETUP_LOG` tail, spinner,
  stage dots from state-dir markers) → Done (exit status, summary, reboot
  button). Includes the `TOPHAT_TUI` Bash guard and the `./tophat` launcher
  with fallback. Runs against `install.sh` as-is otherwise.

  **What M1 actually shipped**, so the next milestone starts from reality:
  Config screen with the three toggles and a stage checklist; Run screen with
  stage dots from `stage-*.done` and a 12-line tail of `latest.log`; Done screen
  with exit status and marker count. `buildArgs`/`tailLines`/`parseMarker` are
  pure modules with tests; the UI has render tests via `@opentui/react/test-utils`.
  **Deferred to M2:** the target-user text input (M1 shows the detected user and
  accepts no override), the resolved-plan preview, and the replacement-package
  preview for the removals toggle.
- [x] **M2 — Stage graph UI.** Done 2026-10-30.
  `install.sh --print-plan` prints the resolved stage list (one per line, stdout
  only, no root needed), so the dependency graph is asked for rather than
  mirrored in TypeScript. `tests/plan_test.sh` pins that contract: closure
  included, failures on stderr, specific dependency edges asserted.
  The config screen shows the resolved plan and labels stages the selection pulls
  in as `(dependency)`. Deliberate deviation from the original sketch: pulled-in
  stages are **labelled, not auto-checked** — a checked box means "I chose this",
  and conflating the two would make the selection unreadable.
  The accept-removals row previews `packages/remove-replaced.packages`
  ("Removes 9: mako, waybar, ...").
- [x] **M3 — Structured events.** Done 2026-10-30.
  With `TOPHAT_TUI=1` the installer appends NDJSON to
  `$SETUP_STATE_DIR/events.ndjson`: `stage_start`, `stage_done` (with seconds),
  `stage_skipped`, `stage_fail`, `command`, `marker`. The stream is truncated at
  the start of each run, so a rerun never inherits stale events, and nothing is
  written for a plain CLI run. Emitted with string substitution and an append —
  no jq, no python.
  `tests/events_test.sh` pins the contract (valid JSON, the event types the TUI
  renders, quotes/backslashes/tabs escaped rather than splitting a line, silent
  unless `TOPHAT_TUI=1`). The run screen draws a vertical board from
  `reduceEvents` — `[x] preflight (12s)`, `[>] repos`, `[!] packaging` — with the
  current command underneath, and falls back to `stage-*.done` markers when no
  event stream exists (a run started by something other than the TUI).
- [x] **M4 — Runtime provisioning (revised).** Done 2026-10-30. Originally: `bun build --compile`
  and ship a binary per architecture. **Rejected on security grounds.** A
  compiled binary embeds a frozen Bun: a CVE in the runtime would only reach
  users when we rebuild and re-publish, so the fix cadence would be our release
  cadence, not Bun's. The TUI is a convenience layer; it should not be the part
  of Tophat that ages worst.

  Instead the launcher provisions a *runtime* and runs the sources from the
  checkout:

  - look for Bun only where its own installer puts it: `$TOPHAT_BUN` (an escape
    hatch), `PATH` (a packaged Bun, or an install whose profile has loaded),
    then `~/.bun/bin/bun` for the current shell;
  - if absent, offer to install it once by running Bun's official installer
    unmodified, so it lands in the documented location and on `PATH` the way
    Bun's own instructions describe;
  - never install silently: `--install-runtime` does it non-interactively, and
    declining falls back to `install.sh` exactly as before.

  Consequence, stated plainly: updates are the user's to apply (`dnf upgrade`
  for a packaged Bun, `bun upgrade` for ours). The TUI shows the running
  runtime version so a stale one is visible rather than silent. No binaries in
  Releases, nothing to re-cut when Bun patches something.
  `./tophat --diagnose` reports what was found and what the launcher would do,
  which is also how the tests exercise the decision without a terminal.

  **The dependency is stated in four places**, because an undisclosed dependency
  is a support ticket: the README prerequisites (marked TUI-only), `./tophat
  --help`, the fallback message when the TUI is skipped for want of Bun, and the
  TUI's own first screen ("runtime: bun x.y.z" plus a keep-it-patched line).
  `--diagnose` adds an `update_hint`.
- [ ] **M5 — Polish.** Error recovery (retry failed stage / open log / abort),
  resume-from-markers UI, theme, keybinding help footer.

## Screens (target UX)

1. **Welcome/detect** — Fedora version, target user, hardware notes (from
   preflight detection helpers, read-only)
2. **Stages** — checklist + resolved plan preview (M2)
3. **Options** — dry-run, verbose, accept-removals (with replacement list),
   target user
4. **Run** — stage board, log tail pane, current command; `[q]` aborts
   (SIGTERM to child)
5. **Done** — status, marker summary, "Reboot now?" (M1: reboot button only
   on success)

Failure view: failed stage highlighted, last ~50 log lines, actions: retry
stage (`--select`), view full log, abort.

## Testing

- `bun test` for pure logic: argv construction from config state, log-tail
  parser, marker watcher, event reducer (M3).
- Integration: a fake engine script (stub `install.sh` that writes markers +
  log lines on a timer) driven by the launcher in CI — no dnf, no root.
- Separate `tui` CI job (bun setup, `bun install --frozen-lockfile`,
  `bun test`, `bun build`). Independent of the five Bash gates; both must pass
  once the TUI lands on `main`.
- Manual: a physical laptop (real GPU) is the TUI test bed.

## Risks / watch items

- **Binary trust + size**: compiled binary is ~50–90 MB; mitigate with
  checksums, signed releases, and the always-available Bash fallback.
- **Logic drift**: any TUI-side reimplementation of Tophat logic is a bug
  waiting to happen — always shell out to `lib/stages.sh`/helpers.
- **OpenTUI churn**: pre-1.0 APIs; pin versions, commit `bun.lock`, and use the
  upstream agent skill (`npx skills add anomalyco/opentui`) when building.
- **aarch64**: verify `bun build --compile` cross-builds; otherwise M4 ships
  x86_64 only and aarch64 falls back to Bash.
