// Stage-marker reading. The TUI shows progress from `stage-*.done` files, which
// the installer already maintains - no extra protocol needed for M1.

import { STAGES, type StageName } from "./stages.ts";

/** Parse the `key=value` body of a marker file. */
export function parseMarker(text: string): Record<string, string> {
  const fields: Record<string, string> = {};
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (trimmed === "" || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    fields[trimmed.slice(0, index).trim()] = trimmed.slice(index + 1).trim();
  }
  return fields;
}

/** Map marker file names (stage-<name>.done) to stage names. */
export function markerStages(fileNames: string[]): Set<StageName> {
  const done = new Set<StageName>();
  for (const name of fileNames) {
    const match = /^stage-(.+)\.done$/.exec(name);
    if (!match) continue;
    const stage = match[1] as StageName;
    if (STAGES.includes(stage)) done.add(stage);
  }
  return done;
}
