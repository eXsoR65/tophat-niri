// Running the installer as a child process.
//
// The TUI configures and observes; it never executes package operations itself.
// stdin is /dev/null so nothing can block on input if a prompt slips through, and
// TOPHAT_TUI=1 tells the installer that it is not attached to a user terminal.

import { spawn, type ChildProcess } from "node:child_process";
import { buildArgs, type Config } from "./config.ts";
import { resolvePaths, type Paths } from "./paths.ts";

export type Engine = {
  child: ChildProcess;
  paths: Paths;
  args: string[];
};

export function startInstall(config: Config, paths: Paths = resolvePaths()): Engine {
  const args = buildArgs(config);
  const child = spawn("bash", [paths.installScript, ...args], {
    cwd: paths.root,
    env: { ...process.env, TOPHAT_TUI: "1", TOPHAT_LOG_DIR: paths.logDir, TOPHAT_STATE_DIR: paths.stateDir },
    stdio: ["ignore", "pipe", "pipe"],
  });
  return { child, paths, args };
}
