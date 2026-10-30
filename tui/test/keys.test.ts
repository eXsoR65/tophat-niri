import { describe, expect, test } from "bun:test";
import { keyAction, moveCursor } from "../src/keys.ts";
import { ROWS } from "../src/rows.ts";

const stageRowIndex = ROWS.findIndex((row) => row.kind === "stage");
const startRowIndex = ROWS.findIndex((row) => row.kind === "start");

describe("keyAction on the config screen", () => {
  test("up and down move the cursor", () => {
    expect(keyAction("config", "up", 0, ROWS)).toEqual({ type: "move", delta: -1 });
    expect(keyAction("config", "down", 0, ROWS)).toEqual({ type: "move", delta: 1 });
  });

  test("space toggles a flag row", () => {
    expect(keyAction("config", "space", 0, ROWS)).toEqual({
      type: "toggle-row",
      row: { kind: "flag", key: "dryRun" },
    });
  });

  test("space toggles a stage row", () => {
    const action = keyAction("config", "space", stageRowIndex, ROWS);
    expect(action.type).toBe("toggle-row");
    if (action.type === "toggle-row") expect(action.row.kind).toBe("stage");
  });

  test("space on the start row starts", () => {
    expect(keyAction("config", "space", startRowIndex, ROWS)).toEqual({ type: "start" });
  });

  test("enter starts from anywhere", () => {
    expect(keyAction("config", "return", 0, ROWS)).toEqual({ type: "start" });
    expect(keyAction("config", "enter", 3, ROWS)).toEqual({ type: "start" });
  });

  test("q quits, unknown keys do nothing", () => {
    expect(keyAction("config", "q", 0, ROWS)).toEqual({ type: "quit" });
    expect(keyAction("config", "x", 0, ROWS)).toEqual({ type: "none" });
  });
});

describe("keyAction on the run and done screens", () => {
  test("q aborts while running, and never starts anything", () => {
    expect(keyAction("run", "q", 0, ROWS)).toEqual({ type: "abort" });
    expect(keyAction("run", "return", 0, ROWS)).toEqual({ type: "none" });
  });

  test("q quits when finished", () => {
    expect(keyAction("done", "q", 0, ROWS)).toEqual({ type: "quit" });
    expect(keyAction("done", "space", 0, ROWS)).toEqual({ type: "none" });
  });
});

describe("moveCursor", () => {
  test("wraps in both directions", () => {
    expect(moveCursor(0, -1, 5)).toBe(4);
    expect(moveCursor(4, 1, 5)).toBe(0);
    expect(moveCursor(2, 1, 5)).toBe(3);
  });

  test("is safe with an empty list", () => {
    expect(moveCursor(0, 1, 0)).toBe(0);
  });
});
