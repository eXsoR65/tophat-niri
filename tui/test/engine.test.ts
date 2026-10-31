import { describe, expect, test } from "bun:test";
import { spawn } from "node:child_process";
import { readFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { startInstall, terminate, type Engine } from "../src/engine.ts";
import { defaultConfig } from "../src/config.ts";
import { readSnapshot } from "../src/snapshot.ts";

async function waitFor(predicate: () => boolean, timeoutMs = 3000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return true;
    await Bun.sleep(25);
  }
  return false;
}

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

describe("terminate", () => {
  test("stops the installer and its children, not just the shell", async () => {
    const pidFile = `/tmp/tophat-engine-test.${process.pid}.pid`;
    // Mirrors how engine.ts spawns: detached, so the shell leads a group and
    // the backgrounded sleep is in it.
    const child = spawn("bash", ["-c", `sleep 30 & echo $! > "${pidFile}"; wait`], {
      detached: true,
      stdio: "ignore",
    });
    const engine = { child, paths: {} as Engine["paths"], args: [] } as Engine;

    const started = await waitFor(() => {
      try {
        return readFileSync(pidFile, "utf8").trim() !== "";
      } catch {
        return false;
      }
    });
    expect(started).toBe(true);

    const grandchild = Number(readFileSync(pidFile, "utf8").trim());
    expect(alive(grandchild)).toBe(true);

    terminate(engine);

    // The point of the fix: the child of the shell dies too.
    const gone = await waitFor(() => !alive(grandchild));
    expect(gone).toBe(true);
  });

  test("is safe to call on a finished or absent run", () => {
    expect(() => terminate(null)).not.toThrow();
    const finished = { exitCode: 0, signalCode: null, pid: 999999 } as unknown as Engine["child"];
    expect(() => terminate({ child: finished } as Engine)).not.toThrow();
  });
});

function fixture(script: string) {
  const root = mkdtempSync(join(tmpdir(), "tophat-engine-regression-"));
  const installScript = join(root, "install.sh");
  writeFileSync(installScript, script);
  return { root, installScript, logDir: join(root, "logs"), stateDir: join(root, "state") };
}

async function bounded(engine: Engine): Promise<number> {
  const timer = setTimeout(() => { void terminate(engine, 25); }, 4000);
  try { return await engine.completion!; }
  finally { clearTimeout(timer); }
}

describe("real engine integration", () => {
  test("drains stdout and stderr beyond pipe capacity without hanging", async () => {
    const paths = fixture(`for ((i=0;i<20000;i++)); do
      printf 'stdout-line-%s\\n' "$i"
      printf 'stderr-line-%s\\n' "$i" >&2
    done
    echo OUTPUT_DONE
    `);
    const engine = startInstall(defaultConfig(""), paths);
    try {
      expect(await bounded(engine)).toBe(0);
      expect(engine.outputTail).toContain("OUTPUT_DONE");
      expect(engine.outputTail!.length).toBeLessThanOrEqual(65536);
    } finally { await terminate(engine, 25); }
  });

  test("isolates simultaneous run streams and preserves final failure data", async () => {
    const paths = fixture(`printf '%s\\n' '{"event":"stage_start","at":1,"stage":"packaging"}' > "$TOPHAT_EVENTS_FILE"
      printf '%s\\n' '{"event":"stage_fail","at":2,"stage":"packaging","exit":"17"}' >> "$TOPHAT_EVENTS_FILE"
      echo FAST_FAILURE >&2
      exit 17
    `);
    const first = startInstall(defaultConfig(""), paths);
    const dry = startInstall({ ...defaultConfig(""), dryRun: true }, paths);
    expect(first.eventsFile).not.toBe(dry.eventsFile);
    expect(await bounded(first)).toBe(17);
    expect(await bounded(dry)).toBe(17);
    const snapshot = readSnapshot(paths, first);
    expect(snapshot.events.map(e => e.event)).toEqual(["stage_start", "stage_fail"]);
    expect(snapshot.logLines.join("\n")).toContain("FAST_FAILURE");
  });

  test("escalates when a descendant ignores TERM, even after its leader exits", async () => {
    const paths = fixture(`bash -c 'trap "" TERM; echo ready > "$1"; while :; do sleep 1; done' _ "$PWD/ready" &
      echo $! > "$PWD/worker.pid"
      wait
    `);
    const engine = startInstall(defaultConfig(""), paths);
    try {
      expect(await waitFor(() => { try { return readFileSync(join(paths.root, "ready"), "utf8").trim() === "ready"; } catch { return false; } })).toBe(true);
      const worker = Number(readFileSync(join(paths.root, "worker.pid"), "utf8").trim());
      const stopping = terminate(engine, 100);
      expect(terminate(engine, 100)).toBe(stopping);
      await stopping;
      await bounded(engine);
      // Linux may briefly retain a killed orphan as a zombie; it is not running.
      expect(await waitFor(() => {
        try { return readFileSync(`/proc/${worker}/stat`, "utf8").split(") ")[1]?.startsWith("Z") ?? false; }
        catch { return true; }
      })).toBe(true);
    } finally {
      await terminate(engine, 25);
    }
  });
});
