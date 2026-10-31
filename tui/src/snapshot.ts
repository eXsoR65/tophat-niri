// One observation path for periodic updates AND the final completion read.
import { readFileSync, readdirSync } from "node:fs";
import type { Engine } from "./engine.ts";
import { logPathFrom, readEvents, type InstallerEvent } from "./events.ts";
import { markerStages } from "./markers.ts";
import { tailLines } from "./logtail.ts";
import { latestLog, type Paths } from "./paths.ts";
import type { StageName } from "./stages.ts";

export type Snapshot = {
  events: InstallerEvent[];
  done?: Set<StageName>;
  logLines: string[];
  logPath: string;
};

export function readSnapshot(paths: Paths, engine: Engine | null, previous: InstallerEvent[] = []): Snapshot {
  const fresh = readEvents(paths, engine?.eventsFile);
  // A managed run must never fall back to another run's global events.
  const events = engine?.eventsFile ? fresh : fresh.length ? fresh : previous;
  const announced = logPathFrom(events);
  const logPath = announced ?? (engine?.eventsFile ? "" : latestLog(paths));
  let logLines = tailLines(engine?.outputTail ?? "", 12);
  if (logPath) {
    try {
      logLines = tailLines(readFileSync(logPath, "utf8"), 12);
    } catch {
      // Before log initialization, stderr/stdout still explain startup failures.
    }
  }
  let done: Set<StageName> | undefined;
  try {
    done = markerStages(readdirSync(paths.stateDir));
  } catch {
    // No markers yet. Keep injected/previous marker state in the view.
  }
  return { events, done, logLines, logPath };
}
