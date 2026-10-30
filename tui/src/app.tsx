// The M1 application: configure -> run -> done.
//
// Deliberately small. M1 proves the loop (configure, launch, watch, finish)
// against the real installer; stage graphs, event streams and distribution come
// in later milestones (see docs/TUI-PLAN.md).

import { useEffect, useRef, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { STAGES, type StageName } from "./stages.ts";
import { buildArgs, defaultConfig, detectedUser, toggleStage, type Config } from "./config.ts";
import { markerStages } from "./markers.ts";
import { tailLines } from "./logtail.ts";
import { latestLog, resolvePaths } from "./paths.ts";
import { startInstall, type Engine } from "./engine.ts";
import { readdirSync, readFileSync } from "node:fs";

export type Screen = "config" | "run" | "done";

type Row = { kind: "flag"; key: "dryRun" | "verbose" | "acceptRemovals" } | { kind: "stage"; stage: StageName } | { kind: "start" };

const ROWS: Row[] = [
  { kind: "flag", key: "dryRun" },
  { kind: "flag", key: "verbose" },
  { kind: "flag", key: "acceptRemovals" },
  ...STAGES.map((stage) => ({ kind: "stage", stage }) as Row),
  { kind: "start" },
];

const FLAG_LABELS: Record<"dryRun" | "verbose" | "acceptRemovals", string> = {
  dryRun: "Dry run (change nothing)",
  verbose: "Verbose (show command output)",
  acceptRemovals: "Allow package removals",
};

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
  const logRef = useRef("");

  // Poll the log and the markers while the installer runs. Both already exist:
  // run_logged writes the log and the stage markers are plain files.
  useEffect(() => {
    if (screen !== "run") return;

    const tick = () => {
      try {
        const text = readFileSync(latestLog(enginePaths), "utf8");
        logRef.current = text;
        setLogLines(tailLines(text, 12));
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
    const name = key.name;

    if (screen === "config") {
      if (name === "up") setCursor((c) => (c - 1 + ROWS.length) % ROWS.length);
      else if (name === "down") setCursor((c) => (c + 1) % ROWS.length);
      else if (name === "space") {
        const row = ROWS[cursor];
        if (!row) return;
        if (row.kind === "flag") setConfig((c) => ({ ...c, [row.key]: !c[row.key] }));
        else if (row.kind === "stage") setConfig((c) => toggleStage(c, row.stage));
        else start();
      } else if (name === "return" || name === "enter") {
        const row = ROWS[cursor];
        if (row?.kind === "start") start();
        else start();
      } else if (name === "q") process.exit(0);
      return;
    }

    if (screen === "run") {
      if (name === "q") engineRef.current?.child.kill("SIGTERM");
      return;
    }

    if (screen === "done" && name === "q") {
      process.exit(0);
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
    const dots = STAGES.map((stage) => `${done.has(stage) ? "[x]" : "[ ]"} ${stage}`).join("   ");
    return (
      <box style={{ flexDirection: "column", padding: 1, gap: 1 }}>
        <text fg="#00b0ff">Tophat - installing</text>
        <text fg="#888888">{dots}</text>
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
