// The M1 application: configure -> run -> done.
//
// Deliberately small. M1 proves the loop (configure, launch, watch, finish)
// against the real installer; stage graphs, event streams and distribution come
// in later milestones (see docs/TUI-PLAN.md).

import { useEffect, useMemo, useRef, useState } from "react";
import { useKeyboard, useRenderer } from "@opentui/react";
import { STAGES, type StageName } from "./stages.ts";
import { defaultConfig, detectedUser, toggleStage, type Config } from "./config.ts";
import { markerStages } from "./markers.ts";
import { tailLines } from "./logtail.ts";
import { latestLog, resolvePaths } from "./paths.ts";
import { startInstall, type Engine } from "./engine.ts";
import { FLAG_LABELS, ROWS } from "./rows.ts";
import { dependencies, fetchPlan, loadRemovals } from "./planner.ts";
import { readEvents, reduceEvents, stateGlyph, type InstallerEvent } from "./events.ts";
import { keyAction, moveCursor } from "./keys.ts";
import { readdirSync, readFileSync } from "node:fs";

export type Screen = "config" | "run" | "done";

// The runtime is provisioned by ./tophat rather than shipped inside a binary, so
// which version is running is worth showing: updates are the user's to apply.
const RUNTIME = typeof Bun !== "undefined" ? `bun ${Bun.version}` : "unknown";

export type AppProps = {
  initialScreen?: Screen;
  initialConfig?: Config;
  initialDone?: StageName[];
  initialExitCode?: number | null;
  paths?: ReturnType<typeof resolvePaths>;
  /** Test seams: never spawn a child process or read the repo. */
  startEngine?: (config: Config) => Engine | null;
  initialPlan?: StageName[];
  initialRemovals?: string[];
  initialEvents?: InstallerEvent[];
  initialAborted?: boolean;
  loadPlan?: (config: Config) => Promise<StageName[]>;
};

export function App({
  initialScreen = "config",
  initialConfig,
  initialDone = [],
  initialExitCode = null,
  paths,
  startEngine,
  initialPlan = [],
  initialRemovals,
  initialEvents = [],
  initialAborted = false,
  loadPlan,
}: AppProps) {
  const renderer = useRenderer();
  // Memoised: a fresh object each render would re-run every effect that depends
  // on the paths, and the ones that set state would then loop.
  const enginePaths = useMemo(() => paths ?? resolvePaths(), [paths]);
  const [screen, setScreen] = useState<Screen>(initialScreen);
  const [config, setConfig] = useState<Config>(initialConfig ?? defaultConfig(detectedUser()));
  const [cursor, setCursor] = useState(0);
  const [logLines, setLogLines] = useState<string[]>([]);
  const [done, setDone] = useState<Set<StageName>>(new Set(initialDone));
  const [exitCode, setExitCode] = useState<number | null>(initialExitCode);
  const [aborted, setAborted] = useState(initialAborted);
  const [elapsed, setElapsed] = useState(0);
  const [plan, setPlan] = useState<StageName[]>(initialPlan);
  const [events, setEvents] = useState<InstallerEvent[]>(initialEvents);
  const [removals, setRemovals] = useState<string[]>(initialRemovals ?? []);

  const engineRef = useRef<Engine | null>(null);
  const startedAtRef = useRef(0);
  // The keyboard handler closes over the state of the last render. Several keys
  // can arrive between renders (key repeat, a paste), so the current row has to
  // be read from a ref rather than from the captured `cursor`.
  const cursorRef = useRef(0);

  // Poll the log and the markers while the installer runs. Both already exist:
  // run_logged writes the log and the stage markers are plain files.
  useEffect(() => {
    if (screen !== "run") return;

    const tick = () => {
      try {
        setLogLines(tailLines(readFileSync(latestLog(enginePaths), "utf8"), 12));
      } catch {
        // No log yet; the first lines appear once the installer starts writing.
      }
      try {
        setDone(markerStages(readdirSync(enginePaths.stateDir)));
      } catch {
        // State dir absent until the first stage completes.
      }
      // Structured events, when the installer is writing them, drive the board.
      // An empty read must not wipe what is already there: the file is truncated
      // at run start, so "" is a normal transient rather than "no events".
      const fromFile = readEvents(enginePaths);
      if (fromFile.length > 0) setEvents(fromFile);
      setElapsed(
        startedAtRef.current === 0 ? 0 : Math.max(0, Math.round((Date.now() - startedAtRef.current) / 1000)),
      );
    };

    tick();
    const timer = setInterval(tick, 400);
    return () => clearInterval(timer);
  }, [screen, enginePaths]);

  // The replacement list is static, so it is read once.
  useEffect(() => {
    if (initialRemovals) return;
    setRemovals(loadRemovals(enginePaths));
  }, [enginePaths, initialRemovals]);

  // The resolved plan comes from lib/stages.sh via `--print-plan`; it is re-asked
  // whenever the selection changes, and stale answers are dropped.
  useEffect(() => {
    if (screen !== "config") return;
    let cancelled = false;
    const load = loadPlan ? loadPlan(config) : fetchPlan(enginePaths, config);
    void load.then((result) => {
      if (!cancelled) setPlan(result);
    });
    return () => {
      cancelled = true;
    };
  }, [config.selected, screen, enginePaths, loadPlan]);

  // Leaving the app must not leave an installer running unattended.
  useEffect(() => {
    return () => {
      engineRef.current?.child.kill("SIGTERM");
    };
  }, []);

  const start = (runConfig: Config = config) => {
    const spawnEngine = startEngine ?? ((cfg: Config) => startInstall(cfg, enginePaths));
    const engine = spawnEngine(runConfig);
    engineRef.current = engine;
    startedAtRef.current = Date.now();
    setAborted(false);
    setExitCode(null);
    setScreen("run");
    engine?.child.on("exit", (code: number | null) => {
      setExitCode(code ?? 1);
      setScreen("done");
    });
  };

  useKeyboard((key) => {
    const action = keyAction(screen, key.name, cursorRef.current, ROWS);

    switch (action.type) {
      case "move":
        // Advance the ref synchronously: state updaters are deferred, so a burst
        // of keys within one batch would otherwise all read the same row.
        cursorRef.current = moveCursor(cursorRef.current, action.delta, ROWS.length);
        setCursor(cursorRef.current);
        break;
      case "toggle-row":
        if (action.row.kind === "flag") {
          const flag = action.row.key;
          setConfig((current) => ({ ...current, [flag]: !current[flag] }));
        } else if (action.row.kind === "stage") {
          // Captured before the updater: narrowing does not survive into the
          // closure, since `action` is a parameter binding.
          const stage = action.row.stage;
          setConfig((current) => toggleStage(current, stage));
        }
        break;
      case "start":
        start();
        break;
      case "quit":
        // OpenTUI restores the terminal inside destroy(); a direct process.exit()
        // would skip that and can leave the terminal in raw mode.
        renderer.destroy();
        break;
      case "abort":
        setAborted(true);
        engineRef.current?.child.kill("SIGTERM");
        break;
      case "retry": {
        // Retry only the stage that failed: the installer resolves its own
        // dependencies, so this cannot produce an incomplete plan.
        const target = failedStage;
        if (target && exitCode !== 0) {
          const retryConfig = { ...config, selected: new Set<StageName>([target]) };
          setConfig(retryConfig);
          start(retryConfig);
        }
        break;
      }
      case "none":
        break;
    }
  });

  const board = reduceEvents(events);
  // The first stage that reported a failure is the one worth retrying.
  const failedStage = [...board.states].find(([, state]) => state === "failed")?.[0] ?? null;

  if (screen === "config") {
    const dependencyStages = dependencies(plan, config);
    const currentRow = ROWS[cursor];

    return (
      <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
        <text fg="#00b0ff">Tophat</text>
        <text fg="#888888">Configure, then run the installer. Nothing is changed until you start.</text>
        <box style={{ flexDirection: "column" }}>
          {ROWS.map((row, index) => {
            const pointer = index === cursor ? ">" : " ";
            if (row.kind === "flag") {
              const on = config[row.key];
              const note =
                row.key === "acceptRemovals" && !on ? "  (DMS-replaced packages stay installed)" : "";
              return (
                <text key={row.key} fg={index === cursor ? "#00b0ff" : undefined}>
                  {pointer} [{on ? "x" : " "}] {FLAG_LABELS[row.key]}
                  {note}
                </text>
              );
            }
            if (row.kind === "stage") {
              const on = config.selected.has(row.stage);
              return (
                <text key={row.stage} fg={index === cursor ? "#00b0ff" : undefined}>
                  {pointer} [{on ? "x" : " "}] {row.stage}
                  {dependencyStages.has(row.stage) ? "  (dependency)" : ""}
                  {done.has(row.stage) ? "  (already done)" : ""}
                </text>
              );
            }
            return (
              <text key="start" fg={index === cursor ? "#00b0ff" : "#00c853"}>
                {pointer} Start install
              </text>
            );
          })}
        </box>
        <text fg="#888888">
          {config.selected.size === 0 ? "All stages selected" : `${config.selected.size} stage(s) selected`}
          {config.targetUser ? `  user: ${config.targetUser}` : ""}
        </text>
        <text fg="#888888">
          Plan: {plan.length > 0 ? plan.join(" -> ") : "(resolving from lib/stages.sh)"}
        </text>
        {currentRow?.kind === "flag" && currentRow.key === "acceptRemovals" ? (
          <text fg="#888888">
            {removals.length > 0
              ? `Removes ${removals.length}: ${removals.slice(0, 6).join(", ")}${removals.length > 6 ? ", ..." : ""}`
              : "No replacement list found"}
          </text>
        ) : null}
        <text fg="#555555">
          space toggle   enter start   q quit   runtime: {RUNTIME}
        </text>
        <text fg="#444444">The TUI runs on Bun; keep it patched (bun upgrade, or dnf upgrade if packaged).</text>
      </box>
    );
  }

  if (screen === "run") {
    const board = reduceEvents(events);
    // Events are richer, but markers work on their own: fall back when a run
    // was started by something other than this TUI.
    const usingEvents = events.length > 0;

    return (
      <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
        <text fg={board.failed ? "red" : "#00b0ff"}>
          {board.failed ? "Tophat - failed" : "Tophat - installing"}
        </text>
        <box style={{ flexDirection: "column" }}>
          {STAGES.map((stage) => {
            const state = usingEvents
              ? (board.states.get(stage) ?? "pending")
              : done.has(stage)
                ? "done"
                : "pending";
            const { glyph, colour } = stateGlyph(state);
            const seconds = board.durations.get(stage);
            return (
              <text key={stage} fg={colour}>
                {glyph} {stage}
                {seconds === undefined ? "" : ` (${seconds}s)`}
              </text>
            );
          })}
        </box>
        {board.currentCommand ? <text fg="#888888">now: {board.currentCommand}</text> : null}
        <text fg="#888888">
          {elapsed}s elapsed{config.dryRun ? "  (dry run)" : ""}
        </text>
        <box style={{ flexDirection: "column", border: true, padding: 1 }}>
          {logLines.length === 0 ? <text fg="#555555">waiting for output...</text> : null}
          {logLines.map((line, index) => (
            <text key={index}>{line}</text>
          ))}
        </box>
        <text fg="#555555">q abort</text>
      </box>
    );
  }

  const ok = exitCode === 0;
  const status = ok ? "Finished successfully" : aborted ? "Aborted" : `Failed (exit ${exitCode})`;
  const colour = ok ? "#00c853" : aborted ? "#ffb300" : "#ff5252";

  return (
    <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
      <text fg={colour}>{status}</text>
      {!ok && failedStage ? <text fg="#888888">Failed in stage: {failedStage}</text> : null}
      <text fg="#888888">
        {done.size} of {STAGES.length} stage markers present
      </text>
      <text fg="#888888">
        {ok
          ? "Reboot to start the graphical session."
          : aborted
            ? "Stopped by you; completed stages are recorded, so a rerun resumes."
            : "See the log below; a rerun resumes from the completed stages."}
      </text>
      <text fg="#555555">log: {latestLog(enginePaths)}</text>
      <text fg="#555555">{!ok && failedStage ? "r retry failed stage   q quit" : "q quit"}</text>
    </box>
  );
}
