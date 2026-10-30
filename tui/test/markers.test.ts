import { describe, expect, test } from "bun:test";
import { markerStages, parseMarker } from "../src/markers.ts";

describe("parseMarker", () => {
  test("reads key=value lines and ignores noise", () => {
    const fields = parseMarker("completed=packaging\nversion=2.7\n\nuser=alice\n# note\n");
    expect(fields).toEqual({ completed: "packaging", version: "2.7", user: "alice" });
  });

  test("keeps values containing = intact", () => {
    expect(parseMarker("completed=a=b\n")).toEqual({ completed: "a=b" });
  });
});

describe("markerStages", () => {
  test("maps stage-*.done files to stage names", () => {
    const done = markerStages(["stage-preflight.done", "stage-repos.done", "stage-repos.config", "notes.txt"]);
    expect([...done]).toEqual(["preflight", "repos"]);
  });

  test("ignores unknown stage names", () => {
    expect([...markerStages(["stage-notastage.done"])]).toEqual([]);
  });
});
