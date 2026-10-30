import { describe, expect, test } from "bun:test";
import { parseEvents, reduceEvents, stateGlyph } from "../src/events.ts";

describe("parseEvents", () => {
  test("parses one JSON object per line", () => {
    const events = parseEvents('{"event":"stage_start","at":1,"stage":"repos"}\n{"event":"stage_done","at":2,"stage":"repos","seconds":"4"}\n');
    expect(events.map((e) => e.event)).toEqual(["stage_start", "stage_done"]);
  });

  test("skips blanks, malformed and partial lines", () => {
    const events = parseEvents('\nnot json\n{"event":"marker","at":1,"stage":"repos"}\n{"event":"stage_d');
    expect(events.map((e) => e.event)).toEqual(["marker"]);
  });
});

describe("reduceEvents", () => {
  const board = reduceEvents([
    { event: "stage_start", at: 1, stage: "preflight" },
    { event: "command", at: 2, stage: "preflight", desc: "dnf upgrade" },
    { event: "stage_done", at: 3, stage: "preflight", seconds: "12" },
    { event: "stage_start", at: 4, stage: "repos" },
    { event: "stage_skipped", at: 5, stage: "extras", reason: "no opt-ins" },
  ]);

  test("tracks each stage state", () => {
    expect(board.states.get("preflight")).toBe("done");
    expect(board.states.get("repos")).toBe("running");
    expect(board.states.get("extras")).toBe("skipped");
    expect(board.states.get("packaging")).toBe("pending");
  });

  test("records durations", () => {
    expect(board.durations.get("preflight")).toBe(12);
  });

  test("remembers the current command and stage", () => {
    expect(board.currentStage).toBe("repos");
  });

  test("a marker implies completion even without a done event", () => {
    const withMarker = reduceEvents([
      { event: "stage_start", at: 1, stage: "config" },
      { event: "marker", at: 2, stage: "config" },
    ]);
    expect(withMarker.states.get("config")).toBe("done");
  });

  test("a failure marks the stage and the run", () => {
    const failed = reduceEvents([
      { event: "stage_start", at: 1, stage: "packaging" },
      { event: "stage_fail", at: 2, stage: "packaging", reason: "dnf failed" },
    ]);
    expect(failed.states.get("packaging")).toBe("failed");
    expect(failed.failed).toBe(true);
  });

  test("unknown stage names are ignored", () => {
    const boardWithUnknown = reduceEvents([{ event: "stage_start", at: 1, stage: "notastage" }]);
    expect(boardWithUnknown.currentStage).toBeNull();
  });
});

describe("stateGlyph", () => {
  test("has a distinct glyph per state", () => {
    expect(stateGlyph("done").glyph).toBe("[x]");
    expect(stateGlyph("running").glyph).toBe("[>]");
    expect(stateGlyph("failed").glyph).toBe("[!]");
    expect(stateGlyph("skipped").glyph).toBe("[-]");
    expect(stateGlyph("pending").glyph).toBe("[ ]");
  });
});
