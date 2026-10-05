# Tophat TUI Plan

Status: **planning** (no code yet)
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
| M1 | `TOPHAT_TUI=1` env guard: skip the two `read </dev/tty` prompts (removal confirm already has the flag path; reboot prompt defaults to "no" and the TUI shows its own reboot button). Without this the child process fights the TUI for the terminal. | ~10 lines |
| M3 | When `TOPHAT_TUI=1`, `run_logged`/`run_stage` additionally emit NDJSON events to `$SETUP_STATE_DIR/events.ndjson`: `stage_start`, `stage_done`, `stage_fail`, `command`, `marker` | ~30 lines |

The TUI also **passes stdin from `/dev/null`** to the installer so nothing can
block on input even if a prompt slips through.

## Milestones

- [ ] **M1 — Scaffold + simple flow.** `tui/` Bun project with
  `@opentui/react`. Screens: Config (target-user, stage multi-select, dry-run /
  verbose / accept-removals toggles) → Run (live `$SETUP_LOG` tail, spinner,
  stage dots from state-dir markers) → Done (exit status, summary, reboot
  button). Includes the `TOPHAT_TUI` Bash guard and the `./tophat` launcher
  with fallback. Runs against `install.sh` as-is otherwise.
- [ ] **M2 — Stage graph UI.** Checklist with dependency visualization: select
  `config` → `preflight/repos/packaging` auto-check, labeled "dependency".
  Resolved plan preview from `lib/stages.sh`. Replacement-package preview for
  the accept-removals toggle (reads `packages/*.replaced`).
- [ ] **M3 — Structured events.** NDJSON protocol (above); per-stage status
  board (pending/running/done/failed/skipped) with durations; current-command
  line.
- [ ] **M4 — Distribution.** `bun build --compile` standalone binary
  (x86_64 + aarch64), published to GitHub Releases by a workflow, versioned
  with `VERSION`. `./tophat` fetches the matching binary to a cache dir when
  missing and online; verifies checksum; falls back to plain install offline.
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
