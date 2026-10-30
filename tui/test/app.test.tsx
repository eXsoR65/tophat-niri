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

  test("done screen reports a failure with its exit code", async () => {
    const frame = await frameOf(<App initialScreen="done" initialExitCode={1} />);
    expect(frame).toContain("Failed (exit 1)");
  });
});
