import { describe, expect, test } from "bun:test";
import { visibleWindow } from "../src/layout.ts";

describe("visibleWindow", () => {
  test("shows everything when the terminal is tall enough", () => {
    expect(visibleWindow(0, 12, 20)).toEqual({ start: 0, end: 12 });
    expect(visibleWindow(11, 12, 12)).toEqual({ start: 0, end: 12 });
  });

  test("keeps the cursor visible near the top and bottom", () => {
    expect(visibleWindow(0, 12, 5)).toEqual({ start: 0, end: 5 });
    expect(visibleWindow(11, 12, 5)).toEqual({ start: 7, end: 12 });
  });

  test("centres the window on the cursor when it can", () => {
    expect(visibleWindow(6, 12, 5)).toEqual({ start: 4, end: 9 });
  });

  test("clamps to the available rows and handles an empty list", () => {
    expect(visibleWindow(0, 3, 10)).toEqual({ start: 0, end: 3 });
    expect(visibleWindow(0, 0, 5)).toEqual({ start: 0, end: 0 });
    expect(visibleWindow(4, 12, 0)).toEqual({ start: 4, end: 5 });
  });
});
