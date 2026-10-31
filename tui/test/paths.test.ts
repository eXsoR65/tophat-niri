import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { resolvePaths } from "../src/paths.ts";

describe("resolvePaths", () => {
  test("finds the checkout without relying on the current directory", () => {
    // The bug this guards: root defaulted to process.cwd(), so running ./tophat
    // from /tmp looked for /tmp/install.sh.
    const paths = resolvePaths({});
    expect(paths.root.endsWith("/")).toBe(false);
    expect(paths.root.endsWith("tophat-niri")).toBe(true);
    expect(existsSync(paths.installScript)).toBe(true);
  });

  test("an explicit root wins, then TOPHAT_ROOT", () => {
    expect(resolvePaths({}, "/x").installScript).toBe("/x/install.sh");
    expect(resolvePaths({ TOPHAT_ROOT: "/y" }).root).toBe("/y");
    expect(resolvePaths({ TOPHAT_ROOT: "/y" }, "/x").root).toBe("/x");
  });

  test("log and state directories can be redirected", () => {
    const paths = resolvePaths({ TOPHAT_LOG_DIR: "/l", TOPHAT_STATE_DIR: "/s" });
    expect(paths.logDir).toBe("/l");
    expect(paths.stateDir).toBe("/s");
  });

  test("TOPHAT_INSTALL override is honoured", () => {
    expect(resolvePaths({ TOPHAT_INSTALL: "/opt/install.sh" }).installScript).toBe("/opt/install.sh");
  });
});
