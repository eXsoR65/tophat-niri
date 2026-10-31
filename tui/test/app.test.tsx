import { describe, expect, test } from "bun:test";
import { testRender } from "@opentui/react/test-utils";
import { act } from "react";
import { App } from "../src/app.tsx";
import { defaultConfig } from "../src/config.ts";

// Renders a frame and waits for the UI to settle rather than guessing at a
// single render pass (the pattern the OpenTUI testing reference recommends).
async function frameOf(node: Parameters<typeof testRender>[0], width = 90, height = 30) {
  const setup = await testRender(node, { width, height });
  try {
    await setup.waitForVisualIdle();
    return setup.captureCharFrame();
  } finally {
    setup.renderer.destroy();
  }
}

describe("App", () => {
  test("config screen lists every stage and the start action", async () => {
    const frame = await frameOf(<App initialScreen="config" />);
    expect(frame).toContain("Tophat");
    for (const stage of ["preflight", "repos", "packaging", "config", "services", "extras", "finalize"]) {
      expect(frame).toContain(stage);
    }
    expect(frame).toContain("Start install");
    expect(frame).toContain("All stages selected");
    // The runtime is provisioned, not embedded, so its version is on screen.
    expect(frame).toMatch(/runtime: bun \d+\.\d+/);
  });

  test("warns when the run would be unprivileged", async () => {
    // The installer refuses to run without root, so the config screen says so.
    // Skipped when the suite itself runs as root, where the warning is absent.
    if (typeof process.getuid === "function" && process.getuid() === 0) return;

    const frame = await frameOf(<App />);
    expect(frame).toContain("Not root");
    expect(frame).toContain("sudo ./tophat");
  });

  test("config screen reflects a selection", async () => {
    const config = { ...defaultConfig("alice"), dryRun: true };
    config.selected.add("packaging");
    const frame = await frameOf(<App initialScreen="config" initialConfig={config} />);
    expect(frame).toContain("1 stage(s) selected");
    expect(frame).toContain("user: alice");
    expect(frame).toContain("Dry run");
  });

  test("run screen shows the stage board and waits for output", async () => {
    const frame = await frameOf(<App initialScreen="run" />);
    expect(frame).toContain("installing");
    expect(frame).toContain("waiting for output");
  });

  test("run screen marks completed stages", async () => {
    const frame = await frameOf(<App initialScreen="run" initialDone={["preflight", "repos"]} />);
    expect(frame).toContain("[x] preflight");
    expect(frame).toContain("[x] repos");
    expect(frame).toContain("[ ] packaging");
  });

  test("run screen renders the event board when events exist", async () => {
    const events = [
      { event: "stage_start", at: 1, stage: "preflight" },
      { event: "command", at: 2, stage: "preflight", desc: "dnf upgrade" },
      { event: "stage_done", at: 3, stage: "preflight", seconds: "12" },
      { event: "stage_start", at: 4, stage: "repos" },
      { event: "command", at: 5, stage: "repos", desc: "dnf makecache" },
    ];
    const frame = await frameOf(<App initialScreen="run" initialEvents={events} />);

    expect(frame).toContain("[x] preflight (12s)");
    expect(frame).toContain("[>] repos");
    // The current command is the *running* stage's, not the last one seen.
    expect(frame).toContain("now: dnf makecache");
    expect(frame).toContain("[ ] packaging");
  });

  test("run screen falls back to markers without events", async () => {
    const frame = await frameOf(<App initialScreen="run" initialDone={["repos"]} />);
    expect(frame).toContain("[x] repos");
    expect(frame).toContain("[ ] preflight");
  });

  test("done screen reports success and marker count", async () => {
    const frame = await frameOf(
      <App initialScreen="done" initialExitCode={0} initialDone={["preflight", "repos"]} />,
    );
    expect(frame).toContain("Finished successfully");
    expect(frame).toContain("2 of 7");
    expect(frame).toContain("Reboot");
  });

  // Interaction tests: these drive the real keyboard path (useKeyboard ->
  // reducer -> state -> render), which a pty cannot do reliably in CI.
  test("space toggles the highlighted option", async () => {
    const setup = await testRender(<App />, { width: 90, height: 30 });
    try {
      await setup.waitForVisualIdle();
      expect(setup.captureCharFrame()).toContain("[ ] Dry run");

      // Key presses come from the renderer's stdin, outside React's event
      // system, so the resulting update has to be flushed inside act().
      await act(async () => {
        setup.mockInput.pressKey(" ");
      });
      await setup.waitForVisualIdle();

      expect(setup.captureCharFrame()).toContain("[x] Dry run");
    } finally {
      setup.renderer.destroy();
    }
  });

  test("arrows move the cursor and space selects the next option", async () => {
    const setup = await testRender(<App />, { width: 90, height: 30 });
    try {
      await setup.waitForVisualIdle();

      await act(async () => {
        setup.mockInput.pressArrow("down");
        setup.mockInput.pressArrow("down");
        setup.mockInput.pressKey(" ");
      });
      await setup.waitForVisualIdle();

      const frame = setup.captureCharFrame();
      expect(frame).toContain("[x] Allow package removals");
      expect(frame).toContain("[ ] Dry run");
    } finally {
      setup.renderer.destroy();
    }
  });

  test("shows the resolved plan and labels dependencies", async () => {
    const config = { ...defaultConfig("") };
    config.selected.add("config");
    const plan = ["preflight", "repos", "packaging", "config"] as const;

    const frame = await frameOf(
      <App
        initialScreen="config"
        initialConfig={config}
        initialPlan={[...plan]}
        initialRemovals={[]}
        loadPlan={() => Promise.resolve([...plan])}
      />,
    );

    expect(frame).toContain("Plan: preflight -> repos -> packaging -> config");
    expect(frame).toContain("config");
    // stages the selection pulls in are labelled, the chosen one is not
    expect(frame).toContain("[ ] preflight  (dependency)");
    expect(frame).toContain("[x] config");
  });

  test("the removals toggle previews what would be removed", async () => {
    const setup = await testRender(
      <App initialRemovals={["mako", "waybar", "wofi"]} loadPlan={() => Promise.resolve([])} />,
      { width: 90, height: 40 },
    );
    try {
      await setup.waitForVisualIdle();
      // Cursor starts on "dry run"; the removals row is two rows down. Each key
      // gets its own act(): the input parser dispatches asynchronously, so two
      // presses inside one act() are not necessarily processed before the frame.
      await act(async () => {
        setup.mockInput.pressArrow("down");
      });
      await act(async () => {
        setup.mockInput.pressArrow("down");
      });
      await setup.waitForVisualIdle();
      const frame = setup.captureCharFrame();
      expect(frame).toContain("Removes 3: mako, waybar, wofi");
    } finally {
      setup.renderer.destroy();
    }
  });

  test("config screen marks stages a previous run already completed", async () => {
    const frame = await frameOf(<App initialDone={["repos", "packaging"]} />);
    expect(frame).toContain("[ ] repos  (already done)");
    expect(frame).toContain("[ ] preflight");
  });

  test("failure screen names the failed stage and offers a retry", async () => {
    const events = [
      { event: "stage_start", at: 1, stage: "packaging" },
      { event: "stage_fail", at: 2, stage: "packaging", reason: "dnf failed", exit: "1" },
    ];
    const frame = await frameOf(
      <App initialScreen="done" initialExitCode={1} initialEvents={events} />,
    );
    expect(frame).toContain("Failed (exit 1)");
    expect(frame).toContain("Failed in stage: packaging");
    expect(frame).toContain("r retry failed stage");
    expect(frame).toContain("/var/log/tophat/latest.log");
  });

  test("retrying runs only the failed stage", async () => {
    const events = [
      { event: "stage_start", at: 1, stage: "packaging" },
      { event: "stage_fail", at: 2, stage: "packaging", reason: "dnf failed" },
    ];
    const started: string[][] = [];

    const setup = await testRender(
      <App
        initialScreen="done"
        initialExitCode={1}
        initialEvents={events}
        startEngine={(cfg) => {
          started.push([...cfg.selected]);
          return null;
        }}
      />,
      { width: 90, height: 30 },
    );
    try {
      await setup.waitForVisualIdle();
      await act(async () => {
        setup.mockInput.pressKey("r");
      });
      await setup.waitForVisualIdle();
    } finally {
      setup.renderer.destroy();
    }

    expect(started).toEqual([["packaging"]]);
  });

  test("an aborted run is not reported as a failure", async () => {
    const frame = await frameOf(<App initialScreen="done" initialExitCode={143} initialAborted />);
    expect(frame).toContain("Aborted");
    expect(frame).toContain("Stopped by you");
    expect(frame).not.toContain("Failed (exit");
  });

  test("a failure with no known stage offers no retry", async () => {
    // Stdin was not ours to interpret: the exit code says failure, but without
    // an event stream there is no stage name to retry.
    const frame = await frameOf(<App initialScreen="done" initialExitCode={1} />);
    expect(frame).toContain("Failed (exit 1)");
    expect(frame).not.toContain("r retry failed stage");
  });

  test("done screen reports a failure with its exit code", async () => {
    const frame = await frameOf(<App initialScreen="done" initialExitCode={1} />);
    expect(frame).toContain("Failed (exit 1)");
  });
});
