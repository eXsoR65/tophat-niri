// NDJSON event stream written by the installer when TOPHAT_TUI=1.
//
// The log is for humans; these events are for the board. Parsing is deliberately
// forgiving: a malformed line is skipped rather than throwing, because a partial
// line is normal while the installer is mid-write.

import { STAGES, type StageName } from "./stages.ts";
import type { Paths } from "./paths.ts";
import { readFileSync } from "node:fs";

export type InstallerEvent = {
  event: string;
  at: number;
  stage?: string;
  seconds?: string;
  desc?: string;
  reason?: string;
  exit?: string;
};

export type StageState = "pending" | "running" | "done" | "skipped" | "failed";

export type StageBoard = {
  states: Map<StageName, StageState>;
  durations: Map<StageName, number>;
  currentCommand: string;
  currentStage: StageName | null;
  failed: boolean;
};

/** Parse an NDJSON stream, skipping blank or malformed lines. */
export function parseEvents(text: string): InstallerEvent[] {
  const events: InstallerEvent[] = [];
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (trimmed === "") continue;
    try {
      const parsed = JSON.parse(trimmed) as InstallerEvent;
      if (typeof parsed === "object" && parsed !== null && typeof parsed.event === "string") {
        events.push(parsed);
      }
    } catch {
      // A half-written final line; the next poll will pick up the whole event.
    }
  }
  return events;
}

/** Fold the stream into per-stage state for the board. */
export function reduceEvents(events: InstallerEvent[]): StageBoard {
  const states = new Map<StageName, StageState>(STAGES.map((stage) => [stage, "pending" as StageState]));
  const durations = new Map<StageName, number>();
  let currentCommand = "";
  let currentStage: StageName | null = null;
  let failed = false;

  const known = (name: string | undefined): StageName | null =>
    name && (STAGES as readonly string[]).includes(name) ? (name as StageName) : null;

  for (const event of events) {
    const stage = known(event.stage);

    switch (event.event) {
      case "stage_start":
        if (stage) {
          states.set(stage, "running");
          currentStage = stage;
          currentCommand = "";
        }
        break;
      case "stage_done":
        if (stage) {
          states.set(stage, "done");
          const seconds = Number(event.seconds ?? "");
          if (Number.isFinite(seconds)) durations.set(stage, seconds);
        }
        break;
      case "stage_skipped":
        if (stage) states.set(stage, "skipped");
        break;
      case "stage_fail":
        if (stage) states.set(stage, "failed");
        failed = true;
        break;
      case "command":
        if (stage === currentStage || stage === null) currentCommand = event.desc ?? "";
        break;
      case "marker":
        // A marker means the stage finished even if its done event was lost.
        if (stage && states.get(stage) !== "failed") states.set(stage, "done");
        break;
      default:
        break;
    }
  }

  return { states, durations, currentCommand, currentStage, failed };
}

/** Read and parse the stream, tolerating an absent file. */
export function readEvents(paths: Paths): InstallerEvent[] {
  try {
    return parseEvents(readFileSync(`${paths.stateDir}/events.ndjson`, "utf8"));
  } catch {
    return [];
  }
}

/** Single character + colour for a stage state. */
export function stateGlyph(state: StageState): { glyph: string; colour: string } {
  switch (state) {
    case "done":
      return { glyph: "[x]", colour: "green" };
    case "running":
      return { glyph: "[>]", colour: "yellow" };
    case "failed":
      return { glyph: "[!]", colour: "red" };
    case "skipped":
      return { glyph: "[-]", colour: "gray" };
    default:
      return { glyph: "[ ]", colour: "gray" };
  }
}
