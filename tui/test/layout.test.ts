import { describe, expect, test } from "bun:test";
import { clipLine, visibleWindow } from "../src/layout.ts";

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

describe("clipLine", () => {
  test("leaves short lines untouched", () => {
    expect(clipLine("dnf upgrade", 20)).toBe("dnf upgrade");
    expect(clipLine("", 20)).toBe("");
  });

  test("truncates to the available cells with one ellipsis", () => {
    expect(clipLine("abcdefghij", 5)).toBe("abcd…");
    expect(clipLine("abcdefghij", 10)).toBe("abcdefghij");
    expect(clipLine("abcdefghij", 1)).toBe("…");
  });

  test("counts code points rather than UTF-16 units", () => {
    expect(clipLine("a😀bc", 3)).toBe("a😀…");
  });
});
