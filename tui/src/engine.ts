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

/**
 * Stop the installer, including whatever it is running.
 *
 * The child is spawned detached, so it leads its own process group. Signalling
 * only the bash process would leave a foreground `dnf` running to completion
 * while the TUI reported "aborted"; the negative pid reaches the group.
 */
export function terminate(engine: Engine | null): void {
  const child = engine?.child;
  const pid = child?.pid;
  if (!child || pid === undefined) return;
  if (child.exitCode !== null || child.signalCode !== null) return;

  try {
    process.kill(-pid, "SIGTERM");
  } catch {
    try {
      child.kill("SIGTERM");
    } catch {
      // Already gone; nothing to stop.
    }
  }
}

export function startInstall(config: Config, paths: Paths = resolvePaths()): Engine {
  const args = buildArgs(config);
  const child = spawn("bash", [paths.installScript, ...args], {
    // Own process group, so terminate() can stop the whole run (see above).
    detached: true,
    cwd: paths.root,
    env: { ...process.env, TOPHAT_TUI: "1", TOPHAT_LOG_DIR: paths.logDir, TOPHAT_STATE_DIR: paths.stateDir },
    stdio: ["ignore", "pipe", "pipe"],
  });
  return { child, paths, args };
}
