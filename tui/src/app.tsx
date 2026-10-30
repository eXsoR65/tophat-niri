// The M1 application: configure -> run -> done.
//
// Deliberately small. M1 proves the loop (configure, launch, watch, finish)
// against the real installer; stage graphs, event streams and distribution come
// in later milestones (see docs/TUI-PLAN.md).

import { useEffect, useRef, useState } from "react";
import { useKeyboard, useRenderer } from "@opentui/react";
import { STAGES, type StageName } from "./stages.ts";
import { defaultConfig, detectedUser, toggleStage, type Config } from "./config.ts";
import { markerStages } from "./markers.ts";
import { tailLines } from "./logtail.ts";
import { latestLog, resolvePaths } from "./paths.ts";
import { startInstall, type Engine } from "./engine.ts";
import { FLAG_LABELS, ROWS } from "./rows.ts";
import { keyAction, moveCursor } from "./keys.ts";
import { readdirSync, readFileSync } from "node:fs";

export type Screen = "config" | "run" | "done";

export type AppProps = {
  initialScreen?: Screen;
  initialConfig?: Config;
  initialDone?: StageName[];
  initialExitCode?: number | null;
  paths?: ReturnType<typeof resolvePaths>;
  /** Test seam: never spawn a child process. */
  startEngine?: (config: Config) => Engine | null;
};

export function App({
  initialScreen = "config",
  initialConfig,
  initialDone = [],
  initialExitCode = null,
  paths,
  startEngine,
}: AppProps) {
  const renderer = useRenderer();
  const enginePaths = paths ?? resolvePaths();
  const [screen, setScreen] = useState<Screen>(initialScreen);
  const [config, setConfig] = useState<Config>(initialConfig ?? defaultConfig(detectedUser()));
  const [cursor, setCursor] = useState(0);
  const [logLines, setLogLines] = useState<string[]>([]);
  const [done, setDone] = useState<Set<StageName>>(new Set(initialDone));
  const [exitCode, setExitCode] = useState<number | null>(initialExitCode);
  const [elapsed, setElapsed] = useState(0);

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
      setElapsed(Math.max(0, Math.round((Date.now() - startedAtRef.current) / 1000)));
    };

    tick();
    const timer = setInterval(tick, 400);
    return () => clearInterval(timer);
  }, [screen, enginePaths]);

  // Leaving the app must not leave an installer running unattended.
  useEffect(() => {
    return () => {
      engineRef.current?.child.kill("SIGTERM");
    };
  }, []);

  const start = () => {
    const spawnEngine = startEngine ?? ((cfg: Config) => startInstall(cfg, enginePaths));
    const engine = spawnEngine(config);
    engineRef.current = engine;
    startedAtRef.current = Date.now();
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
        engineRef.current?.child.kill("SIGTERM");
        break;
      case "none":
        break;
    }
  });

  if (screen === "config") {
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
        <text fg="#555555">space toggle   enter start   q quit</text>
      </box>
    );
  }

  if (screen === "run") {
    return (
      <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
        <text fg="#00b0ff">Tophat - installing</text>
        <text>
          {STAGES.map((stage, index) => (
            <span key={stage} fg={done.has(stage) ? "green" : "gray"}>
              {`${done.has(stage) ? "[x]" : "[ ]"} ${stage}`}
              {index < STAGES.length - 1 ? "   " : ""}
            </span>
          ))}
        </text>
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
  return (
    <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
      <text fg={ok ? "#00c853" : "#ff5252"}>{ok ? "Finished successfully" : `Failed (exit ${exitCode})`}</text>
      <text fg="#888888">
        {done.size} of {STAGES.length} stage markers present
      </text>
      <text fg="#888888">{ok ? "Reboot to start the graphical session." : "See the log above; rerun to resume."}</text>
      <text fg="#555555">q quit</text>
    </box>
  );
}
