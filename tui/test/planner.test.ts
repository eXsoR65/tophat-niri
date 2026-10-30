import { describe, expect, test } from "bun:test";
import { dependencies, parseListFile, parsePlan, planArgs } from "../src/planner.ts";
import { defaultConfig, toggleStage } from "../src/config.ts";
import type { StageName } from "../src/stages.ts";

describe("planArgs", () => {
  test("no selection asks for the default plan", () => {
    expect(planArgs(defaultConfig(""))).toEqual([]);
  });

  test("a subset is passed in execution order", () => {
    let config = toggleStage(defaultConfig(""), "services");
    config = toggleStage(config, "preflight");
    expect(planArgs(config)).toEqual(["--select", "preflight,services"]);
  });

  test("selecting everything is the same as selecting nothing", () => {
    let config = defaultConfig("");
    for (const stage of ["preflight", "repos", "packaging", "config", "services", "extras", "finalize"] as const) {
      config = toggleStage(config, stage);
    }
    expect(planArgs(config)).toEqual([]);
  });
});

describe("parsePlan", () => {
  test("reads one stage per line, in order", () => {
    expect(parsePlan("preflight\nrepos\npackaging\n")).toEqual(["preflight", "repos", "packaging"]);
  });

  test("ignores blanks, duplicates and unknown names", () => {
    expect(parsePlan("\npreflight\n\npreflight\nnotastage\n")).toEqual(["preflight"]);
  });
});

describe("dependencies", () => {
  const plan: StageName[] = ["preflight", "repos", "packaging", "config"];

  test("with a selection, unselected plan stages are dependencies", () => {
    let config = toggleStage(defaultConfig(""), "config");
    expect([...dependencies(plan, config)]).toEqual(["preflight", "repos", "packaging"]);
  });

  test("with no selection nothing is labelled a dependency", () => {
    expect([...dependencies(plan, defaultConfig(""))]).toEqual([]);
  });
});

describe("parseListFile", () => {
  test("drops comments and blanks, keeps order", () => {
    expect(parseListFile("# header\nmako\nwaybar\n\n# note\nwofi\n")).toEqual(["mako", "waybar", "wofi"]);
  });

  test("handles a trailing comment on an entry", () => {
    expect(parseListFile("mako # replaced\n")).toEqual(["mako"]);
  });
});
