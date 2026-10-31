// The installer owns system changes; the TUI owns and observes one child group.
import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildArgs, type Config } from "./config.ts";
import { resolvePaths, type Paths } from "./paths.ts";

export type Engine = {
  child: ChildProcess;
  paths: Paths;
  args: string[];
  eventsFile?: string;
  outputTail?: string;
  completion?: Promise<number>;
  stopping?: Promise<void>;
  settled?: boolean;
};

const delay = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function groupExists(pid: number): boolean {
  try {
    process.kill(-pid, 0);
    return true;
  } catch {
    return false;
  }
}

/** Bounded shutdown, retaining ownership even if the bash leader exits first.
 * Never retry signals against a completed run (its PID might have been reused).
 * TERM gives package tools time to stop; KILL prevents a TERM-resistant child
 * continuing unattended. Like any forced interruption, this may leave package
 * recovery work or a stale installer lock; it is not a transactional rollback.
 */
export function terminate(engine: Engine | null, graceMs = 750): Promise<void> {
  if (!engine) return Promise.resolve();
  if (engine.stopping) return engine.stopping;
  const { child } = engine;
  const pid = child.pid;
  if (pid === undefined || engine.settled) return Promise.resolve();
  if (!engine.completion && (child.exitCode !== null || child.signalCode !== null)) return Promise.resolve();

  engine.stopping = (async () => {
    try {
      process.kill(-pid, "SIGTERM");
    } catch {
      // A failed spawn or already-reaped group needs no further signals.
      return;
    }
    const deadline = Date.now() + graceMs;
    while (groupExists(pid) && Date.now() < deadline) await delay(25);
    if (groupExists(pid)) {
      try {
        process.kill(-pid, "SIGKILL");
      } catch {
        // Group exited between the probe and signal.
      }
    }
  })();
  return engine.stopping;
}

export function startInstall(config: Config, paths: Paths = resolvePaths()): Engine {
  const args = buildArgs(config);
  // Every TUI run, including a dry-run or retry, gets its own event stream.
  // A rejected second installer cannot read or erase another run's progress.
  const runDir = mkdtempSync(join(tmpdir(), "tophat-tui-"));
  const eventsFile = join(runDir, "events.ndjson");
  const child = spawn("bash", [paths.installScript, ...args], {
    detached: true,
    cwd: paths.root,
    env: {
      ...process.env,
      TOPHAT_TUI: "1",
      TOPHAT_EVENTS_FILE: eventsFile,
      TOPHAT_LOG_DIR: paths.logDir,
      TOPHAT_STATE_DIR: paths.stateDir,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const engine: Engine = { child, paths, args, eventsFile, outputTail: "" };
  // Always drain both pipes. The file log is authoritative, but unconsumed tee
  // or dry-run output would fill a pipe and deadlock the installer.
  const capture = (chunk: Buffer) => {
    engine.outputTail = ((engine.outputTail ?? "") + chunk.toString()).slice(-65536);
  };
  child.stdout?.on("data", capture);
  child.stderr?.on("data", capture);
  engine.completion = new Promise<number>((resolve) => {
    let spawnError = false;
    child.once("error", (error) => {
      spawnError = true;
      engine.outputTail = ((engine.outputTail ?? "") + `\n${error.message}`).slice(-65536);
    });
    // close, not exit: output and the final event writes have finished. On abort
    // also wait for the bounded group shutdown, not just the bash leader.
    child.once("close", (code) => {
      void (async () => {
        await engine.stopping;
        engine.settled = true;
        resolve(spawnError ? 1 : (code ?? 1));
      })();
    });
  });
  return engine;
}
