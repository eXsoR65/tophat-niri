import { describe, expect, test } from "bun:test";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { terminate, type Engine } from "../src/engine.ts";

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
