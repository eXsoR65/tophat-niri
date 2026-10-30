import { describe, expect, test } from "bun:test";
import { buildArgs, defaultConfig, detectedUser, toggleStage } from "../src/config.ts";

describe("buildArgs", () => {
  test("defaults to every stage and no flags", () => {
    expect(buildArgs(defaultConfig(""))).toEqual([]);
  });

  test("selected stages are emitted in execution order, not click order", () => {
    let config = defaultConfig("");
    config = toggleStage(config, "services");
    config = toggleStage(config, "preflight");
    expect(buildArgs(config)).toEqual(["--select", "preflight,services"]);
  });

  test("selecting every stage is the same as selecting none", () => {
    let config = defaultConfig("");
    for (const stage of ["preflight", "repos", "packaging", "config", "services", "extras", "finalize"] as const) {
      config = toggleStage(config, stage);
    }
    expect(buildArgs(config)).toEqual([]);
  });

  test("toggling twice removes the stage", () => {
    let config = toggleStage(defaultConfig(""), "config");
    config = toggleStage(config, "config");
    expect(buildArgs(config)).toEqual([]);
  });

  test("flags are emitted in a stable order", () => {
    const config = { ...defaultConfig(""), dryRun: true, verbose: true, force: true, acceptRemovals: true };
    expect(buildArgs(config)).toEqual(["--dry-run", "--verbose", "--force", "--accept-package-removals"]);
  });

  test("a target user is passed through, blank means omitted", () => {
    expect(buildArgs({ ...defaultConfig("alice") })).toEqual(["--target-user", "alice"]);
    expect(buildArgs(defaultConfig("   "))).toEqual([]);
  });
});

describe("detectedUser", () => {
  test("prefers the sudo invoker", () => {
    expect(detectedUser({ SUDO_USER: "alice", USER: "root" })).toBe("alice");
  });

  test("falls back to USER, then empty", () => {
    expect(detectedUser({ USER: "bob" })).toBe("bob");
    expect(detectedUser({})).toBe("");
  });
});
