import { describe, expect, test } from "bun:test";
import { appendedSince, tailLines } from "../src/logtail.ts";

describe("tailLines", () => {
  test("keeps the last n lines and drops the trailing newline", () => {
    expect(tailLines("a\nb\nc\n", 2)).toEqual(["b", "c"]);
  });

  test("returns everything when the log is shorter than n", () => {
    expect(tailLines("only\n", 10)).toEqual(["only"]);
  });

  test("empty input and zero length are handled", () => {
    expect(tailLines("", 5)).toEqual([]);
    expect(tailLines("a\nb", 0)).toEqual([]);
  });
});

describe("appendedSince", () => {
  test("returns only the new part of an appended log", () => {
    expect(appendedSince("one\n", "one\ntwo\n")).toBe("two\n");
  });

  test("returns everything when the log was truncated or rotated", () => {
    expect(appendedSince("one\ntwo\n", "fresh\n")).toBe("fresh\n");
    expect(appendedSince("", "first\n")).toBe("first\n");
  });
});
